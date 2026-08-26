using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;

namespace BlackSpiritHub;

/// <summary>
/// Executes the repository-only real-image OCR regression suite. Fixture paths
/// are accepted only from the explicit command-line test hook and never from the
/// application bridge or a user screenshot request.
/// </summary>
internal static class RecipeBookOcrFixtureRunner
{
	private const int SupportedSchemaVersion = 4;
	private const int MaximumManifestBytes = 1_000_000;
	private const int FailureExitCode = 269;
	private const double MinimumRequiredBorderGradeConfidence = 0.70;

	internal static int Run(string applicationBaseDirectory, string manifestPath)
	{
		try
		{
			FixtureRunSummary summary = RunAsync(
				applicationBaseDirectory,
				manifestPath,
				CancellationToken.None).GetAwaiter().GetResult();
			Console.WriteLine(JsonSerializer.Serialize(summary));
			return 0;
		}
		catch (Exception exception)
		{
			Console.Error.WriteLine($"Recipe Book OCR fixture regression failed: {exception.Message}");
			return FailureExitCode;
		}
	}

	private static async System.Threading.Tasks.Task<FixtureRunSummary> RunAsync(
		string applicationBaseDirectory,
		string manifestPath,
		CancellationToken cancellationToken)
	{
		if (string.IsNullOrWhiteSpace(manifestPath))
		{
			throw new InvalidDataException("A fixture manifest path is required.");
		}

		string resolvedManifestPath = Path.GetFullPath(manifestPath);
		FileInfo manifestFile = new(resolvedManifestPath);
		if (!manifestFile.Exists || manifestFile.Length is <= 0 or > MaximumManifestBytes)
		{
			throw new InvalidDataException("The fixture manifest is missing, empty, or too large.");
		}

		JsonSerializerOptions options = new()
		{
			PropertyNameCaseInsensitive = true,
			UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
		};
		FixtureManifest manifest = JsonSerializer.Deserialize<FixtureManifest>(
			await File.ReadAllTextAsync(resolvedManifestPath, cancellationToken),
			options) ?? throw new InvalidDataException("The fixture manifest is empty.");
		ValidateManifest(manifest);

		string fixtureRoot = Path.GetDirectoryName(resolvedManifestPath)
			?? throw new InvalidDataException("The fixture manifest has no containing directory.");
		string fixtureRootPrefix = Path.GetFullPath(fixtureRoot)
			.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
			+ Path.DirectorySeparatorChar;

		List<FixtureCaseSummary> summaries = new();
		using RecipeBookScreenshotService service = new(applicationBaseDirectory);
		foreach (FixtureCase fixtureCase in manifest.Cases!)
		{
			cancellationToken.ThrowIfCancellationRequested();
			FixtureTruthSet truthSet = manifest.TruthSets![fixtureCase.Truth!.Set];
			string imagePath = ResolveFixturePath(fixtureRootPrefix, fixtureCase.File);
			byte[] imageBytes = await File.ReadAllBytesAsync(imagePath, cancellationToken);
			try
			{
				ValidateFixtureBytes(fixtureCase, imageBytes);
				RecipeBookScreenshotRequest request = new(
					Path.GetFileName(imagePath),
					"image/png",
					Convert.ToBase64String(imageBytes));
				RecipeBookScreenshotResult result = await service.AnalyzeAsync(request, cancellationToken);
				summaries.Add(ValidateResult(fixtureCase, truthSet, result));
			}
			finally
			{
				CryptographicOperations.ZeroMemory(imageBytes);
			}
		}

		return new FixtureRunSummary(
			manifest.SchemaVersion,
			summaries.Count,
			summaries.Sum(summary => summary.Slots),
			summaries.Sum(summary => summary.VisibleLabels),
			summaries.Sum(summary => summary.ResolvedLabels),
			summaries.Sum(summary => summary.AbstainedLabels),
			summaries.Sum(summary => summary.AssumedOne),
			summaries.Sum(summary => summary.MaterialClassAssertions),
			summaries.Sum(summary => summary.BorderGradeAssertions),
			summaries.Min(summary => summary.MinimumBorderGradeConfidence),
			summaries);
	}

	private static void ValidateManifest(FixtureManifest manifest)
	{
		if (manifest.SchemaVersion != SupportedSchemaVersion
			|| manifest.TruthSets is null
			|| manifest.TruthSets.Count == 0
			|| manifest.Cases is null
			|| manifest.Cases.Count == 0)
		{
			throw new InvalidDataException("The fixture manifest schema or inventory is invalid.");
		}

		foreach ((string key, FixtureTruthSet truthSet) in manifest.TruthSets)
		{
			if (string.IsNullOrWhiteSpace(key)
				|| truthSet.Rows is null
				|| truthSet.Rows.Count == 0
				|| truthSet.Rows.Any(row => row is null || row.Count == 0))
			{
				throw new InvalidDataException($"Truth set '{key}' is empty or malformed.");
			}

			int columns = truthSet.Rows[0].Count;
			if (truthSet.Rows.Any(row => row.Count != columns))
			{
				throw new InvalidDataException($"Truth set '{key}' is not rectangular.");
			}

			int visibleLabels = 0;
			foreach (FixtureTruthCell cell in truthSet.Rows.SelectMany(row => row))
			{
				if (cell.Value <= 0)
				{
					throw new InvalidDataException($"Truth set '{key}' contains a non-positive value.");
				}
				if (string.IsNullOrWhiteSpace(cell.Display))
				{
					if (!cell.AssumedOne || cell.Value != 1)
					{
						throw new InvalidDataException($"Truth set '{key}' contains an invalid unlabeled slot.");
					}
				}
				else
				{
					if (cell.AssumedOne)
					{
						throw new InvalidDataException($"Truth set '{key}' marks a visible label as assumed-one.");
					}
					visibleLabels++;
				}
			}
			if (visibleLabels != truthSet.VisibleLabelCount)
			{
				throw new InvalidDataException($"Truth set '{key}' visible-label count is inconsistent.");
			}
		}

		HashSet<string> caseIds = new(StringComparer.Ordinal);
		foreach (FixtureCase fixtureCase in manifest.Cases)
		{
			if (string.IsNullOrWhiteSpace(fixtureCase.Id)
				|| !caseIds.Add(fixtureCase.Id)
				|| string.IsNullOrWhiteSpace(fixtureCase.File)
				|| fixtureCase.Sha256?.Length != 64
				|| fixtureCase.Bytes <= 0
				|| fixtureCase.Width <= 0
				|| fixtureCase.Height <= 0
				|| fixtureCase.Grid is null
				|| fixtureCase.Truth is null
				|| fixtureCase.RequiredResolved is null
				|| fixtureCase.RequiredSuggestions is null
				|| fixtureCase.RequiredMaterialClasses is null
				|| fixtureCase.RequiredBorderGrades is null
				|| fixtureCase.RequiredBorderGrades.Count == 0
				|| !manifest.TruthSets.TryGetValue(fixtureCase.Truth.Set, out FixtureTruthSet? truthSet))
			{
				throw new InvalidDataException("A fixture case is missing required metadata.");
			}

			FixtureGrid grid = fixtureCase.Grid;
			if (grid.Columns <= 0
				|| grid.Rows <= 0
				|| grid.Left < 0
				|| grid.Pitch <= 0
				|| grid.CellWidth <= 0
				|| grid.CellHeight <= 0
				|| grid.CellWidth > grid.Pitch
				|| grid.RowTops is null
				|| grid.RowTops.Count != grid.Rows
				|| grid.RowTops.Any(top => top < 0)
				|| grid.BoxTolerance is < 0 or > 8
				|| (long)grid.Left + (long)(grid.Columns - 1) * grid.Pitch + grid.CellWidth > fixtureCase.Width
				|| (long)grid.RowTops[^1] + grid.CellHeight > fixtureCase.Height)
			{
				throw new InvalidDataException($"Fixture '{fixtureCase.Id}' has invalid grid geometry.");
			}

			if (fixtureCase.Truth.RowOffset < 0
				|| fixtureCase.Truth.ColumnOffset < 0
				|| fixtureCase.Truth.RowOffset + grid.Rows > truthSet.Rows!.Count
				|| fixtureCase.Truth.ColumnOffset + grid.Columns > truthSet.Rows[0].Count)
			{
				throw new InvalidDataException($"Fixture '{fixtureCase.Id}' escapes its truth-set bounds.");
			}

			int visibleLabels = 0;
			for (int row = 0; row < grid.Rows; row++)
			{
				for (int column = 0; column < grid.Columns; column++)
				{
					FixtureTruthCell cell = truthSet.Rows[fixtureCase.Truth.RowOffset + row]
						[fixtureCase.Truth.ColumnOffset + column];
					if (!string.IsNullOrWhiteSpace(cell.Display))
					{
						visibleLabels++;
					}
				}
			}

			HashSet<(int Row, int Column)> requiredResolved = new();
			foreach (FixtureCoordinate coordinate in fixtureCase.RequiredResolved)
			{
				if (coordinate.Row <= 0
					|| coordinate.Row > grid.Rows
					|| coordinate.Column <= 0
					|| coordinate.Column > grid.Columns
					|| !requiredResolved.Add((coordinate.Row, coordinate.Column)))
				{
					throw new InvalidDataException(
						$"Fixture '{fixtureCase.Id}' contains an invalid or duplicate required-resolved coordinate.");
				}

				FixtureTruthCell requiredCell = truthSet.Rows[fixtureCase.Truth.RowOffset + coordinate.Row - 1]
					[fixtureCase.Truth.ColumnOffset + coordinate.Column - 1];
				if (string.IsNullOrWhiteSpace(requiredCell.Display) || requiredCell.AssumedOne)
				{
					throw new InvalidDataException(
						$"Fixture '{fixtureCase.Id}' requires resolution of an unlabeled slot at "
						+ $"r{coordinate.Row}c{coordinate.Column}.");
				}
			}

			HashSet<(int Row, int Column)> requiredSuggestions = new();
			foreach (FixtureCoordinate coordinate in fixtureCase.RequiredSuggestions)
			{
				if (coordinate.Row <= 0
					|| coordinate.Row > grid.Rows
					|| coordinate.Column <= 0
					|| coordinate.Column > grid.Columns
					|| !requiredSuggestions.Add((coordinate.Row, coordinate.Column)))
				{
					throw new InvalidDataException(
						$"Fixture '{fixtureCase.Id}' contains an invalid or duplicate required-suggestion coordinate.");
				}

				FixtureTruthCell requiredCell = truthSet.Rows[fixtureCase.Truth.RowOffset + coordinate.Row - 1]
					[fixtureCase.Truth.ColumnOffset + coordinate.Column - 1];
				if (string.IsNullOrWhiteSpace(requiredCell.Display)
					|| requiredCell.AssumedOne
					|| requiredResolved.Contains((coordinate.Row, coordinate.Column)))
				{
					throw new InvalidDataException(
						$"Fixture '{fixtureCase.Id}' requires an invalid or already-confirmed suggestion at "
						+ $"r{coordinate.Row}c{coordinate.Column}.");
				}
			}

			HashSet<(int Row, int Column)> requiredBorderGrades = new();
			foreach (FixtureBorderGradeExpectation expectation in fixtureCase.RequiredBorderGrades)
			{
				if (expectation.Row <= 0
					|| expectation.Row > grid.Rows
					|| expectation.Column <= 0
					|| expectation.Column > grid.Columns
					|| expectation.Grade is < 0 or > 2
					|| !requiredBorderGrades.Add((expectation.Row, expectation.Column)))
				{
					throw new InvalidDataException(
						$"Fixture '{fixtureCase.Id}' contains an invalid or duplicate required-border-grade coordinate.");
				}
			}

			HashSet<(int Row, int Column)> requiredMaterialClasses = new();
			foreach (FixtureMaterialClassExpectation expectation in fixtureCase.RequiredMaterialClasses)
			{
				if (expectation.Row <= 0
					|| expectation.Row > grid.Rows
					|| expectation.Column <= 0
					|| expectation.Column > grid.Columns
					|| expectation.MaterialClass is not ("material" or "nonMaterial" or "uncertain")
					|| !requiredMaterialClasses.Add((expectation.Row, expectation.Column)))
				{
					throw new InvalidDataException(
						$"Fixture '{fixtureCase.Id}' contains an invalid or duplicate required-material-class coordinate.");
				}
			}

			if (fixtureCase.MinimumResolved < requiredResolved.Count
				|| fixtureCase.MinimumResolved > visibleLabels)
			{
				throw new InvalidDataException(
					$"Fixture '{fixtureCase.Id}' has an invalid minimum-resolved threshold.");
			}
		}
	}

	private static string ResolveFixturePath(string fixtureRootPrefix, string relativePath)
	{
		if (Path.IsPathRooted(relativePath)
			|| relativePath.IndexOfAny(Path.GetInvalidPathChars()) >= 0
			|| relativePath.Replace('\\', '/').Split('/').Contains("..", StringComparer.Ordinal))
		{
			throw new InvalidDataException("A fixture image path is unsafe.");
		}

		string resolved = Path.GetFullPath(Path.Combine(fixtureRootPrefix, relativePath));
		if (!resolved.StartsWith(fixtureRootPrefix, StringComparison.OrdinalIgnoreCase)
			|| !string.Equals(Path.GetExtension(resolved), ".png", StringComparison.OrdinalIgnoreCase)
			|| !File.Exists(resolved))
		{
			throw new InvalidDataException("A fixture image is missing or escaped its fixture directory.");
		}
		return resolved;
	}

	private static void ValidateFixtureBytes(FixtureCase fixtureCase, byte[] bytes)
	{
		if (bytes.LongLength != fixtureCase.Bytes)
		{
			throw new InvalidDataException($"Fixture '{fixtureCase.Id}' byte count changed.");
		}
		string digest = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
		if (!string.Equals(digest, fixtureCase.Sha256, StringComparison.Ordinal))
		{
			throw new InvalidDataException($"Fixture '{fixtureCase.Id}' digest changed.");
		}
	}

	private static FixtureCaseSummary ValidateResult(
		FixtureCase fixtureCase,
		FixtureTruthSet truthSet,
		RecipeBookScreenshotResult result)
	{
		FixtureGrid expectedGrid = fixtureCase.Grid!;
		if (result.Width != fixtureCase.Width
			|| result.Height != fixtureCase.Height
			|| result.Grid.Columns != expectedGrid.Columns
			|| result.Grid.Rows != expectedGrid.Rows)
		{
			throw new InvalidDataException(
				$"Fixture '{fixtureCase.Id}' grid changed: expected "
				+ $"{expectedGrid.Columns}x{expectedGrid.Rows} in {fixtureCase.Width}x{fixtureCase.Height}, "
				+ $"received {result.Grid.Columns}x{result.Grid.Rows} in {result.Width}x{result.Height}.");
		}

		int expectedSlotCount = checked(expectedGrid.Columns * expectedGrid.Rows);
		if (result.Slots.Count != expectedSlotCount)
		{
			throw new InvalidDataException(
				$"Fixture '{fixtureCase.Id}' returned {result.Slots.Count} slots; expected {expectedSlotCount}.");
		}

		Dictionary<(int Row, int Column), RecipeBookScreenshotSlot> slots;
		try
		{
			slots = result.Slots.ToDictionary(slot => (slot.Row, slot.Column));
		}
		catch (ArgumentException exception)
		{
			throw new InvalidDataException($"Fixture '{fixtureCase.Id}' returned duplicate slot coordinates.", exception);
		}

		int visibleLabels = 0;
		int resolvedLabels = 0;
		int abstainedLabels = 0;
		int assumedOne = 0;
		double minimumBorderGradeConfidence = 1;
		HashSet<(int Row, int Column)> requiredResolved = fixtureCase.RequiredResolved!
			.Select(coordinate => (coordinate.Row - 1, coordinate.Column - 1))
			.ToHashSet();
		HashSet<(int Row, int Column)> requiredSuggestions = fixtureCase.RequiredSuggestions!
			.Select(coordinate => (coordinate.Row - 1, coordinate.Column - 1))
			.ToHashSet();
		foreach (FixtureMaterialClassExpectation expectation in fixtureCase.RequiredMaterialClasses!)
		{
			RecipeBookScreenshotSlot slot = slots[(expectation.Row - 1, expectation.Column - 1)];
			bool? expectedMaterialEligible = expectation.MaterialClass switch
			{
				"material" => true,
				"nonMaterial" => false,
				"uncertain" => null,
				_ => throw new InvalidDataException(
					$"Fixture '{fixtureCase.Id}' contains an unsupported material class.")
			};
			if (slot.IconMaterialEligible != expectedMaterialEligible)
			{
				throw new InvalidDataException(
					$"Fixture '{fixtureCase.Id}' r{expectation.Row}c{expectation.Column} must resolve "
					+ $"materialClass={expectation.MaterialClass}; received "
					+ $"{(slot.IconMaterialEligible is bool actual ? actual.ToString().ToLowerInvariant() : "null")}.");
			}
		}
		foreach (FixtureBorderGradeExpectation expectation in fixtureCase.RequiredBorderGrades!)
		{
			RecipeBookScreenshotSlot slot = slots[(expectation.Row - 1, expectation.Column - 1)];
			if (slot.BorderGrade != expectation.Grade
				|| !double.IsFinite(slot.BorderGradeConfidence)
				|| slot.BorderGradeConfidence < MinimumRequiredBorderGradeConfidence
				|| slot.BorderGradeConfidence > 1)
			{
				throw new InvalidDataException(
					$"Fixture '{fixtureCase.Id}' r{expectation.Row}c{expectation.Column} must resolve border grade "
					+ $"{expectation.Grade} with confidence at least {MinimumRequiredBorderGradeConfidence:F2}; received "
					+ $"grade {slot.BorderGrade?.ToString() ?? "null"} at confidence {slot.BorderGradeConfidence:F4}.");
			}

			minimumBorderGradeConfidence = Math.Min(minimumBorderGradeConfidence, slot.BorderGradeConfidence);
		}
		for (int row = 0; row < expectedGrid.Rows; row++)
		{
			for (int column = 0; column < expectedGrid.Columns; column++)
			{
				if (!slots.TryGetValue((row, column), out RecipeBookScreenshotSlot? slot))
				{
					throw new InvalidDataException($"Fixture '{fixtureCase.Id}' is missing r{row + 1}c{column + 1}.");
				}

				ValidateBox(fixtureCase.Id, expectedGrid, slot, row, column);
				FixtureTruthCell expected = truthSet.Rows![fixtureCase.Truth!.RowOffset + row]
					[fixtureCase.Truth.ColumnOffset + column];
				if (expected.AssumedOne)
				{
					if (slot.QuantitySuggestedValue is long guessedValue)
					{
						if (slot.QuantityValue is not null
							|| slot.QuantityAssumedOne
							|| guessedValue < 1
							|| guessedValue > int.MaxValue
							|| string.IsNullOrWhiteSpace(slot.QuantityText)
							|| !RecipeBookScreenshotService.TryParseQuantity(
								slot.QuantityText,
								out long parsedGuess,
								out bool parsedGuessApproximate)
							|| parsedGuess != guessedValue
							|| parsedGuessApproximate != slot.QuantityApproximate)
						{
							throw new InvalidDataException(
								$"Fixture '{fixtureCase.Id}' r{row + 1}c{column + 1} produced an inconsistent review guess "
								+ $"for an otherwise unlabeled slot: '{slot.QuantityText}' ({guessedValue}).");
						}

						// The user-facing policy intentionally shows every strict OCR guess.
						// A false glyph read on an unlabeled item must remain review-only rather
						// than being treated as a trusted quantity or a silent assumed-one.
						continue;
					}

					if (!slot.QuantityAssumedOne
						|| slot.QuantityValue != 1
						|| !string.IsNullOrWhiteSpace(slot.QuantityText)
						|| slot.QuantityApproximate)
					{
						throw new InvalidDataException(
							$"Fixture '{fixtureCase.Id}' r{row + 1}c{column + 1} must remain an unlabeled assumed-one slot; "
							+ $"received text '{slot.QuantityText}', value {slot.QuantityValue?.ToString() ?? "null"}, assumed-one={slot.QuantityAssumedOne}.");
					}
					assumedOne++;
					continue;
				}

				visibleLabels++;
				if (slot.QuantityAssumedOne)
				{
					throw new InvalidDataException(
						$"Fixture '{fixtureCase.Id}' r{row + 1}c{column + 1} has a visible label "
						+ "and must never be treated as an assumed quantity of one.");
				}

				bool expectedApproximate = expected.Display!.EndsWith("K", StringComparison.OrdinalIgnoreCase)
					|| expected.Display.EndsWith("M", StringComparison.OrdinalIgnoreCase);
				if (slot.QuantitySuggestedValue is long suggestedValue)
				{
					if (suggestedValue < 1
						|| suggestedValue > int.MaxValue
						|| string.IsNullOrWhiteSpace(slot.QuantityText)
						|| !RecipeBookScreenshotService.TryParseQuantity(
							slot.QuantityText,
							out long parsedSuggestedTextValue,
							out bool parsedSuggestedTextApproximate)
						|| parsedSuggestedTextValue != suggestedValue
						|| slot.QuantityApproximate != parsedSuggestedTextApproximate)
					{
						throw new InvalidDataException(
							$"Fixture '{fixtureCase.Id}' r{row + 1}c{column + 1} produced an inconsistent review suggestion: "
							+ $"received '{slot.QuantityText}' ({suggestedValue}), "
							+ $"approximate={slot.QuantityApproximate}.");
					}
					if (requiredSuggestions.Contains((row, column))
						&& (suggestedValue != expected.Value
							|| !string.Equals(slot.QuantityText, expected.Display, StringComparison.Ordinal)))
					{
						throw new InvalidDataException(
							$"Fixture '{fixtureCase.Id}' r{row + 1}c{column + 1} must preserve the pinned "
							+ $"review suggestion '{expected.Display}' ({expected.Value}); received "
							+ $"'{slot.QuantityText}' ({suggestedValue}).");
					}
				}
				else if (requiredSuggestions.Contains((row, column)))
				{
					throw new InvalidDataException(
						$"Fixture '{fixtureCase.Id}' r{row + 1}c{column + 1} must emit the pinned "
						+ $"review suggestion '{expected.Display}' ({expected.Value}).");
				}

				if (slot.QuantityValue is long quantityValue)
				{
					if (slot.QuantitySuggestedValue is not null)
					{
						throw new InvalidDataException(
							$"Fixture '{fixtureCase.Id}' r{row + 1}c{column + 1} must not duplicate a confirmed quantity as a review suggestion.");
					}
					if (quantityValue != expected.Value)
					{
						throw new InvalidDataException(
							$"Fixture '{fixtureCase.Id}' r{row + 1}c{column + 1} produced an unsafe importable "
							+ $"quantity: expected '{expected.Display}' ({expected.Value}), received "
							+ $"'{slot.QuantityText}' ({quantityValue}).");
					}

					if (string.IsNullOrWhiteSpace(slot.QuantityText)
						|| !RecipeBookScreenshotService.TryParseQuantity(
							slot.QuantityText,
							out long parsedTextValue,
							out bool parsedTextApproximate)
						|| parsedTextValue != expected.Value
						|| parsedTextApproximate != expectedApproximate
						|| slot.QuantityApproximate != expectedApproximate)
					{
						throw new InvalidDataException(
							$"Fixture '{fixtureCase.Id}' r{row + 1}c{column + 1} returned inconsistent "
							+ "OCR text or K/M state for an importable quantity.");
					}
					resolvedLabels++;
				}
				else
				{
					if (string.IsNullOrWhiteSpace(slot.QuantityText))
					{
						throw new InvalidDataException(
							$"Fixture '{fixtureCase.Id}' r{row + 1}c{column + 1} abstained without "
							+ "preserving raw OCR text for manual review.");
					}
					if (requiredResolved.Contains((row, column)))
					{
						throw new InvalidDataException(
							$"Fixture '{fixtureCase.Id}' r{row + 1}c{column + 1} must resolve the pinned "
							+ $"regression label '{expected.Display}' ({expected.Value}).");
					}
					abstainedLabels++;
				}
			}
		}

		if (resolvedLabels < fixtureCase.MinimumResolved)
		{
			throw new InvalidDataException(
				$"Fixture '{fixtureCase.Id}' resolved {resolvedLabels} of {visibleLabels} visible labels; "
				+ $"the calibrated minimum is {fixtureCase.MinimumResolved}.");
		}

		return new FixtureCaseSummary(
			fixtureCase.Id,
			expectedSlotCount,
			visibleLabels,
			resolvedLabels,
			abstainedLabels,
			assumedOne,
			fixtureCase.RequiredMaterialClasses.Count,
			fixtureCase.RequiredBorderGrades.Count,
			Math.Round(minimumBorderGradeConfidence, 4));
	}

	private static void ValidateBox(
		string caseId,
		FixtureGrid grid,
		RecipeBookScreenshotSlot slot,
		int row,
		int column)
	{
		int expectedX = checked(grid.Left + column * grid.Pitch);
		int expectedY = grid.RowTops![row];
		if (Math.Abs(slot.Box.X - expectedX) > grid.BoxTolerance
			|| Math.Abs(slot.Box.Y - expectedY) > grid.BoxTolerance
			|| Math.Abs(slot.Box.Width - grid.CellWidth) > grid.BoxTolerance
			|| Math.Abs(slot.Box.Height - grid.CellHeight) > grid.BoxTolerance)
		{
			throw new InvalidDataException(
				$"Fixture '{caseId}' r{row + 1}c{column + 1} box changed: "
				+ $"expected {expectedX},{expectedY},{grid.CellWidth},{grid.CellHeight}; "
				+ $"received {slot.Box.X},{slot.Box.Y},{slot.Box.Width},{slot.Box.Height}.");
		}
	}

	private sealed class FixtureManifest
	{
		public int SchemaVersion { get; init; }
		public Dictionary<string, FixtureTruthSet>? TruthSets { get; init; }
		public List<FixtureCase>? Cases { get; init; }
	}

	private sealed class FixtureTruthSet
	{
		public int VisibleLabelCount { get; init; }
		public List<List<FixtureTruthCell>>? Rows { get; init; }
	}

	private sealed class FixtureTruthCell
	{
		public string? Display { get; init; }
		public long Value { get; init; }
		public bool AssumedOne { get; init; }
	}

	private sealed class FixtureCase
	{
		public string Id { get; init; } = string.Empty;
		public string File { get; init; } = string.Empty;
		public string Sha256 { get; init; } = string.Empty;
		public long Bytes { get; init; }
		public int Width { get; init; }
		public int Height { get; init; }
		public FixtureGrid? Grid { get; init; }
		public int MinimumResolved { get; init; } = -1;
		public List<FixtureCoordinate>? RequiredResolved { get; init; }
		public List<FixtureCoordinate>? RequiredSuggestions { get; init; }
		public List<FixtureMaterialClassExpectation>? RequiredMaterialClasses { get; init; }
		public List<FixtureBorderGradeExpectation>? RequiredBorderGrades { get; init; }
		public FixtureTruthMap? Truth { get; init; }
	}

	private sealed class FixtureCoordinate
	{
		public int Row { get; init; }
		public int Column { get; init; }
	}

	private sealed class FixtureBorderGradeExpectation
	{
		public int Row { get; init; }
		public int Column { get; init; }
		public int Grade { get; init; } = -1;
	}

	private sealed class FixtureMaterialClassExpectation
	{
		public int Row { get; init; }
		public int Column { get; init; }
		public string MaterialClass { get; init; } = string.Empty;
	}

	private sealed class FixtureGrid
	{
		public int Columns { get; init; }
		public int Rows { get; init; }
		public int Left { get; init; }
		public int Pitch { get; init; }
		public int CellWidth { get; init; }
		public int CellHeight { get; init; }
		public List<int>? RowTops { get; init; }
		public int BoxTolerance { get; init; }
	}

	private sealed class FixtureTruthMap
	{
		public string Set { get; init; } = string.Empty;
		public int RowOffset { get; init; }
		public int ColumnOffset { get; init; }
	}

	private sealed record FixtureCaseSummary(
		string Id,
		int Slots,
		int VisibleLabels,
		int ResolvedLabels,
		int AbstainedLabels,
		int AssumedOne,
		int MaterialClassAssertions,
		int BorderGradeAssertions,
		double MinimumBorderGradeConfidence);

	private sealed record FixtureRunSummary(
		int SchemaVersion,
		int CaseCount,
		int SlotCount,
		int VisibleLabelCount,
		int ResolvedLabelCount,
		int AbstainedLabelCount,
		int AssumedOneCount,
		int MaterialClassAssertionCount,
		int BorderGradeAssertionCount,
		double MinimumBorderGradeConfidence,
		IReadOnlyList<FixtureCaseSummary> Cases);
}
