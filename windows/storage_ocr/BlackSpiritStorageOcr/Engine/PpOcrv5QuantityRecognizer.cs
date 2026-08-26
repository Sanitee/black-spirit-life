using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.ML.OnnxRuntime;

namespace BlackSpiritHub;

/// <summary>
/// Runs the official English PP-OCRv5 mobile recognition model locally over
/// caller-supplied quantity-line crops. Crop generation and result selection
/// are injectable so screenshot geometry policy stays outside the model layer.
/// </summary>
internal sealed class PpOcrv5QuantityRecognizer : IDisposable
{
	internal const int InputChannels = 3;
	internal const int InputHeight = 48;
	internal const int InputWidth = 320;
	internal const int CharacterDictionaryCount = 436;
	internal const int OutputClassCount = 438;
	internal const int MaximumBatchSize = 8;
	internal const int MaximumCrops = 192;
	internal const int MaximumVariantsPerCrop = 8;

	internal const string ModelSha256 = "C3461ADD59BB4323ECBA96A492AB75E06DDA42467C9E3D0C18DB5D1D21924BE8";
	internal const double MainConsensusConfidenceFloor = 0.50;
	internal const double SingleGlyphConsensusConfidenceFloor = 0.90;

	private const string InputName = "x";
	private const string OutputName = "fetch_name_0";
	private const int BlankClassIndex = 0;
	private const int SpaceClassIndex = OutputClassCount - 1;
	private const int MinimumReliableSlotSize = 45;
	private const double RequiredLeftContextRatio = 0.12;
	private const int NumericBeamWidth = 32;
	private const double NumericSuggestionPosteriorFloor = 0.55;
	private const double NumericSuggestionMarginFloor = 0.20;
	private const double NumericSuggestionRawConfidenceFloor = 0.45;
	private const int NumericSuggestionMinimumViewAgreement = 2;
	private const string NumericCtcCharacters = "0123456789.,:KM";
	private static readonly Regex SeparatorQuantityPattern = new(
		@"^[0-9]{1,3}[:,][0-9][KM]$",
		RegexOptions.CultureInvariant | RegexOptions.NonBacktracking);
	private static readonly Regex StrictQuantityPattern = new(
		@"^(?:[0-9]{1,5}|[0-9]{1,3}\.[0-9][KM])$",
		RegexOptions.CultureInvariant | RegexOptions.NonBacktracking);

	private readonly InferenceSession session;
	private readonly IReadOnlyList<string> characterDictionary;
	private readonly IReadOnlyList<NumericCtcClass> numericCtcClasses;
	private readonly PpOcrv5QuantityCropVariantFactory cropVariantFactory;
	private readonly PpOcrv5QuantityCandidateRanker candidateRanker;
	private bool disposed;

	internal PpOcrv5QuantityRecognizer(
		string applicationBaseDirectory,
		PpOcrv5QuantityCropVariantFactory? cropVariantFactory = null,
		PpOcrv5QuantityCandidateRanker? candidateRanker = null)
	{
		if (string.IsNullOrWhiteSpace(applicationBaseDirectory))
		{
			throw new ArgumentException("The application directory is required.", nameof(applicationBaseDirectory));
		}

		string assetRoot = Path.Combine(
			Path.GetFullPath(applicationBaseDirectory),
			"Assets",
			"RecipeBook",
			"ocr",
			"ppocrv5");
		string modelPath = Path.Combine(assetRoot, "en_PP-OCRv5_mobile_rec.onnx");
		ValidateAssetHash(modelPath);
		this.cropVariantFactory = cropVariantFactory ?? CreateProductionCropVariants;
		this.candidateRanker = candidateRanker ?? SelectStrictConsensus;

		OrtEnv.Instance().DisableTelemetryEvents();
		using SessionOptions options = new()
		{
			EnableCpuMemArena = true,
			EnableMemoryPattern = true,
			ExecutionMode = ExecutionMode.ORT_SEQUENTIAL,
			GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL,
			InterOpNumThreads = 1,
			IntraOpNumThreads = Math.Clamp(Environment.ProcessorCount / 2, 1, 4),
			LogSeverityLevel = OrtLoggingLevel.ORT_LOGGING_LEVEL_ERROR
		};
		session = new InferenceSession(modelPath, options);
		ValidateModelContract(session);
		characterDictionary = LoadCharacterDictionary(session.ModelMetadata);
		numericCtcClasses = LoadNumericCtcClasses(characterDictionary);
	}

	/// <summary>
	/// Recognizes source-slot rectangles in input order. Each rectangle is the full
	/// detected material slot, not a pre-cropped text line. The default factory
	/// derives three calibrated, unpadded quantity views from every slot. The
	/// recognizer owns and disposes those variants; the screenshot remains owned
	/// by the caller.
	/// </summary>
	internal IReadOnlyList<PpOcrv5QuantityRecognition> Recognize(
		Bitmap screenshot,
		IReadOnlyList<Rectangle> crops,
		CancellationToken cancellationToken)
	{
		ObjectDisposedException.ThrowIf(disposed, this);
		ArgumentNullException.ThrowIfNull(screenshot);
		ArgumentNullException.ThrowIfNull(crops);
		if (crops.Count > MaximumCrops)
		{
			throw new ArgumentOutOfRangeException(nameof(crops), $"At most {MaximumCrops} quantity crops can be recognized at once.");
		}
		if (crops.Count == 0)
		{
			return Array.Empty<PpOcrv5QuantityRecognition>();
		}

		Rectangle imageBounds = new(0, 0, screenshot.Width, screenshot.Height);
		List<PendingVariant> pending = new();
		List<PpOcrv5QuantityCropVariant> ownedVariants = new();
		try
		{
			for (int sourceIndex = 0; sourceIndex < crops.Count; sourceIndex++)
			{
				cancellationToken.ThrowIfCancellationRequested();
				Rectangle crop = crops[sourceIndex];
				if (crop.Width < 1
					|| crop.Height < 1
					|| crop.X < 0
					|| crop.Y < 0
					|| !imageBounds.Contains(crop))
				{
					throw new ArgumentOutOfRangeException(nameof(crops), "Every quantity crop must be positive and contained by the screenshot.");
				}

				IReadOnlyList<PpOcrv5QuantityCropVariant> variants =
					cropVariantFactory(screenshot, crop)
					?? throw new InvalidOperationException("The quantity crop-variant factory returned null.");
				if (variants.Count is < 1 or > MaximumVariantsPerCrop)
				{
					throw new InvalidOperationException($"Each quantity crop requires between 1 and {MaximumVariantsPerCrop} bounded variants.");
				}

				HashSet<string> variantIds = new(StringComparer.Ordinal);
				foreach (PpOcrv5QuantityCropVariant variant in variants)
				{
					if (variant is null)
					{
						throw new InvalidOperationException("The quantity crop-variant factory returned a null variant.");
					}
					ownedVariants.Add(variant);
					if (string.IsNullOrWhiteSpace(variant.Id)
						|| !variantIds.Add(variant.Id)
						|| variant.Image.Width < 1
						|| variant.Image.Height < 1)
					{
						throw new InvalidOperationException("Every quantity crop variant requires a unique ID and a non-empty bitmap.");
					}
					pending.Add(new PendingVariant(sourceIndex, variant));
				}
			}

			List<PpOcrv5QuantityCandidate>[] candidatesBySource = Enumerable.Range(0, crops.Count)
				.Select(_ => new List<PpOcrv5QuantityCandidate>())
				.ToArray();
			for (int offset = 0; offset < pending.Count; offset += MaximumBatchSize)
			{
				cancellationToken.ThrowIfCancellationRequested();
				int count = Math.Min(MaximumBatchSize, pending.Count - offset);
				float[] inputBuffer = new float[checked(count * InputChannels * InputHeight * InputWidth)];
				for (int batchIndex = 0; batchIndex < count; batchIndex++)
				{
					WriteNormalizedInput(
						pending[offset + batchIndex].Variant.Image,
						inputBuffer,
						batchIndex);
				}

				using RunOptions runOptions = new();
				using CancellationTokenRegistration cancellationRegistration = cancellationToken.Register(
					static state => ((RunOptions)state!).Terminate = true,
					runOptions);
				using OrtValue input = OrtValue.CreateTensorValueFromMemory(
					inputBuffer,
					new long[] { count, InputChannels, InputHeight, InputWidth });
				using IDisposableReadOnlyCollection<OrtValue> outputs = RunInference(
					runOptions,
					input,
					cancellationToken);
				OrtValue output = outputs.Single();
				OrtTensorTypeAndShapeInfo outputInfo = output.GetTensorTypeAndShape();
				long[] shape = outputInfo.Shape;
				if (shape.Length != 3
					|| shape[0] != count
					|| shape[1] < 1
					|| shape[2] != OutputClassCount
					|| outputInfo.ElementCount != checked(shape[0] * shape[1] * shape[2]))
				{
					throw new InvalidDataException("The bundled PP-OCRv5 model returned an unexpected tensor shape.");
				}

				ReadOnlySpan<float> probabilities = output.GetTensorDataAsSpan<float>();
				int timeSteps = checked((int)shape[1]);
				int valuesPerSample = checked(timeSteps * OutputClassCount);
				for (int batchIndex = 0; batchIndex < count; batchIndex++)
				{
					PendingVariant item = pending[offset + batchIndex];
					PpOcrv5QuantityCandidate candidate = DecodeCtc(
						item.Variant.Id,
						probabilities.Slice(batchIndex * valuesPerSample, valuesPerSample),
						timeSteps);
					candidatesBySource[item.SourceIndex].Add(candidate);
				}
			}

			PpOcrv5QuantityRecognition[] results = new PpOcrv5QuantityRecognition[crops.Count];
			for (int sourceIndex = 0; sourceIndex < crops.Count; sourceIndex++)
			{
				IReadOnlyList<PpOcrv5QuantityCandidate> candidates = candidatesBySource[sourceIndex].AsReadOnly();
				PpOcrv5QuantityDecision decision = candidateRanker(
					crops[sourceIndex],
					candidates)
					?? throw new InvalidOperationException("The quantity candidate ranker returned null.");
				results[sourceIndex] = new PpOcrv5QuantityRecognition(crops[sourceIndex], decision, candidates);
			}
			return results;
		}
		finally
		{
			foreach (PpOcrv5QuantityCropVariant variant in ownedVariants)
			{
				variant.Dispose();
			}
		}
	}

	internal static void ValidateAssetHash(string modelPath)
	{
		if (!File.Exists(modelPath))
		{
			throw new InvalidDataException("The bundled PP-OCRv5 recognition model is missing.");
		}

		using (FileStream model = File.OpenRead(modelPath))
		{
			string modelHash = Convert.ToHexString(SHA256.HashData(model));
			if (!string.Equals(modelHash, ModelSha256, StringComparison.Ordinal))
			{
				throw new InvalidDataException("The bundled PP-OCRv5 recognition model failed its integrity check.");
			}
		}
	}

	private IDisposableReadOnlyCollection<OrtValue> RunInference(
		RunOptions runOptions,
		OrtValue input,
		CancellationToken cancellationToken)
	{
		try
		{
			return session.Run(
				runOptions,
				new Dictionary<string, OrtValue>(StringComparer.Ordinal) { [InputName] = input },
				new[] { OutputName });
		}
		catch (Exception exception) when (cancellationToken.IsCancellationRequested)
		{
			throw new OperationCanceledException("PP-OCRv5 quantity recognition was cancelled.", exception, cancellationToken);
		}
	}

	private PpOcrv5QuantityCandidate DecodeCtc(
		string variantId,
		ReadOnlySpan<float> probabilities,
		int timeSteps)
	{
		StringBuilder text = new();
		double confidenceTotal = 0;
		double minimumConfidence = 1;
		int emittedCount = 0;
		int previousClass = -1;
		for (int timeStep = 0; timeStep < timeSteps; timeStep++)
		{
			ReadOnlySpan<float> classes = probabilities.Slice(timeStep * OutputClassCount, OutputClassCount);
			int bestClass = 0;
			float bestProbability = classes[0];
			for (int classIndex = 1; classIndex < classes.Length; classIndex++)
			{
				if (classes[classIndex] > bestProbability)
				{
					bestProbability = classes[classIndex];
					bestClass = classIndex;
				}
			}

			if (bestClass != BlankClassIndex && bestClass != previousClass)
			{
				string token = bestClass == SpaceClassIndex
					? " "
					: characterDictionary[bestClass - 1];
				text.Append(token);
				double boundedProbability = float.IsFinite(bestProbability)
					? Math.Clamp(bestProbability, 0, 1)
					: 0;
				boundedProbability = Math.Round(boundedProbability, 5, MidpointRounding.ToEven);
				confidenceTotal += boundedProbability;
				minimumConfidence = Math.Min(minimumConfidence, boundedProbability);
				emittedCount++;
			}
			previousClass = bestClass;
		}

		string decoded = text.ToString();
		double confidence = emittedCount == 0
			? 0
			: Math.Round(confidenceTotal / emittedCount, 5, MidpointRounding.ToEven);
		string? normalizedToken = NormalizeStrictQuantityToken(decoded);
		// The ordinary greedy read is both faster and better calibrated for the
		// common case. Run the constrained beam only when that read is illegal but
		// still visibly quantity-like; this keeps full screenshots fast and avoids
		// manufacturing numeric guesses from item artwork or truly empty slots.
		PpOcrv5NumericCandidate numeric = normalizedToken is null
			&& LooksLikeMalformedQuantity(decoded)
			? DecodeNumericGrammarCtc(probabilities, timeSteps)
			: PpOcrv5NumericCandidate.Empty;
		return new PpOcrv5QuantityCandidate(
			variantId,
			decoded,
			confidence,
			Math.Round(emittedCount == 0 ? 0 : minimumConfidence, 5, MidpointRounding.ToEven),
			normalizedToken,
			numeric.Token,
			numeric.Posterior,
			numeric.LogMargin);
	}

	private static bool LooksLikeMalformedQuantity(string value)
	{
		string candidate = value.Trim().ToUpperInvariant();
		if (candidate.Length is < 2 or > 8
			|| !candidate.Any(character => character is >= '0' and <= '9'))
		{
			return false;
		}
		int quantityCharacters = candidate.Count(character =>
			character is >= '0' and <= '9'
			|| character is '.' or ',' or ':' or 'K' or 'M');
		return quantityCharacters >= candidate.Length - 1;
	}

	/// <summary>
	/// Decodes the same PP-OCR tensor a second time with the inventory amount
	/// grammar applied while paths are still being explored. This is different
	/// from replacing letters after OCR: impossible letters never enter the
	/// beam, while weak but real punctuation/digit evidence remains available.
	/// </summary>
	private PpOcrv5NumericCandidate DecodeNumericGrammarCtc(
		ReadOnlySpan<float> probabilities,
		int timeSteps)
	{
		Dictionary<string, NumericCtcBeam> beam = new(StringComparer.Ordinal)
		{
			[string.Empty] = new NumericCtcBeam(0, double.NegativeInfinity)
		};
		for (int timeStep = 0; timeStep < timeSteps; timeStep++)
		{
			ReadOnlySpan<float> classes = probabilities.Slice(timeStep * OutputClassCount, OutputClassCount);
			double blankLogProbability = SafeLogProbability(classes[BlankClassIndex]);
			Dictionary<string, NumericCtcBeam> next = new(StringComparer.Ordinal);
			foreach ((string prefix, NumericCtcBeam scores) in beam)
			{
				double total = LogSumExp(scores.BlankLogProbability, scores.NonBlankLogProbability);
				AddBlankProbability(next, prefix, total + blankLogProbability);
				foreach (NumericCtcClass numericClass in numericCtcClasses)
				{
					double characterLogProbability = SafeLogProbability(classes[numericClass.ClassIndex]);
					bool repeated = prefix.Length > 0 && prefix[^1] == numericClass.Character;
					if (repeated)
					{
						AddNonBlankProbability(
							next,
							prefix,
							scores.NonBlankLogProbability + characterLogProbability);
					}

					string extended = string.Concat(prefix, numericClass.Character);
					if (!IsStrictQuantityPrefix(extended))
					{
						continue;
					}
					double source = repeated ? scores.BlankLogProbability : total;
					AddNonBlankProbability(next, extended, source + characterLogProbability);
				}
			}

			beam = next
				.OrderByDescending(entry => LogSumExp(
					entry.Value.BlankLogProbability,
					entry.Value.NonBlankLogProbability))
				.ThenBy(entry => entry.Key, StringComparer.Ordinal)
				.Take(NumericBeamWidth)
				.ToDictionary(entry => entry.Key, entry => entry.Value, StringComparer.Ordinal);
		}

		Dictionary<string, double> complete = new(StringComparer.Ordinal);
		foreach ((string rawToken, NumericCtcBeam scores) in beam)
		{
			string? normalized = NormalizeStrictQuantityToken(rawToken);
			if (normalized is null)
			{
				continue;
			}
			double pathProbability = LogSumExp(scores.BlankLogProbability, scores.NonBlankLogProbability);
			complete[normalized] = complete.TryGetValue(normalized, out double existing)
				? LogSumExp(existing, pathProbability)
				: pathProbability;
		}
		if (complete.Count == 0)
		{
			return PpOcrv5NumericCandidate.Empty;
		}

		KeyValuePair<string, double>[] ranked = complete
			.OrderByDescending(entry => entry.Value)
			.ThenBy(entry => entry.Key, StringComparer.Ordinal)
			.ToArray();
		double completeTotal = ranked
			.Select(entry => entry.Value)
			.Aggregate(double.NegativeInfinity, LogSumExp);
		double posterior = Math.Exp(Math.Min(0, ranked[0].Value - completeTotal));
		double margin = ranked.Length == 1
			? double.PositiveInfinity
			: ranked[0].Value - ranked[1].Value;
		return new PpOcrv5NumericCandidate(
			ranked[0].Key,
			Math.Round(Math.Clamp(posterior, 0, 1), 5, MidpointRounding.ToEven),
			double.IsPositiveInfinity(margin)
				? margin
				: Math.Round(Math.Max(0, margin), 5, MidpointRounding.ToEven));
	}

	private static IReadOnlyList<NumericCtcClass> LoadNumericCtcClasses(
		IReadOnlyList<string> dictionary)
	{
		List<NumericCtcClass> classes = new(NumericCtcCharacters.Length);
		foreach (char character in NumericCtcCharacters)
		{
			int dictionaryIndex = -1;
			for (int index = 0; index < dictionary.Count; index++)
			{
				if (string.Equals(dictionary[index], character.ToString(), StringComparison.Ordinal))
				{
					dictionaryIndex = index;
					break;
				}
			}
			if (dictionaryIndex < 0)
			{
				throw new InvalidDataException(
					$"The bundled PP-OCRv5 dictionary has no required quantity character '{character}'.");
			}
			classes.Add(new NumericCtcClass(dictionaryIndex + 1, character));
		}
		return classes.AsReadOnly();
	}

	private static bool IsStrictQuantityPrefix(string rawPrefix)
	{
		if (rawPrefix.Length == 0)
		{
			return true;
		}
		string prefix = rawPrefix.Replace(',', '.').Replace(':', '.');
		if (prefix[0] is < '1' or > '9')
		{
			return false;
		}
		int separator = prefix.IndexOf('.');
		if (separator < 0)
		{
			return prefix.Length <= 5 && prefix.All(character => character is >= '0' and <= '9');
		}
		if (separator is < 1 or > 3
			|| prefix.IndexOf('.', separator + 1) >= 0)
		{
			return false;
		}
		string whole = prefix[..separator];
		string tail = prefix[(separator + 1)..];
		if (!whole.All(character => character is >= '0' and <= '9')
			|| tail.Length > 2)
		{
			return false;
		}
		return tail.Length switch
		{
			0 => true,
			1 => tail[0] is >= '0' and <= '9',
			2 => tail[0] is >= '0' and <= '9' && tail[1] is 'K' or 'M',
			_ => false
		};
	}

	private static double SafeLogProbability(float probability)
	{
		double bounded = float.IsFinite(probability)
			? Math.Clamp(probability, 1e-30f, 1f)
			: 1e-30;
		return Math.Log(bounded);
	}

	private static double LogSumExp(double left, double right)
	{
		if (double.IsNegativeInfinity(left)) return right;
		if (double.IsNegativeInfinity(right)) return left;
		double maximum = Math.Max(left, right);
		return maximum + Math.Log(Math.Exp(left - maximum) + Math.Exp(right - maximum));
	}

	private static void AddBlankProbability(
		IDictionary<string, NumericCtcBeam> target,
		string prefix,
		double probability)
	{
		NumericCtcBeam current = target.TryGetValue(prefix, out NumericCtcBeam existing)
			? existing
			: NumericCtcBeam.Empty;
		target[prefix] = current with
		{
			BlankLogProbability = LogSumExp(current.BlankLogProbability, probability)
		};
	}

	private static void AddNonBlankProbability(
		IDictionary<string, NumericCtcBeam> target,
		string prefix,
		double probability)
	{
		NumericCtcBeam current = target.TryGetValue(prefix, out NumericCtcBeam existing)
			? existing
			: NumericCtcBeam.Empty;
		target[prefix] = current with
		{
			NonBlankLogProbability = LogSumExp(current.NonBlankLogProbability, probability)
		};
	}

	private static void WriteNormalizedInput(Bitmap source, float[] destination, int batchIndex)
	{
		int resizedWidth = Math.Min(
			InputWidth,
			Math.Max(1, (int)Math.Ceiling(InputHeight * source.Width / (double)source.Height)));
		using Bitmap resized = new(resizedWidth, InputHeight, PixelFormat.Format24bppRgb);
		using (Graphics graphics = Graphics.FromImage(resized))
		using (ImageAttributes attributes = new())
		{
			graphics.Clear(Color.Black);
			graphics.CompositingMode = CompositingMode.SourceCopy;
			graphics.InterpolationMode = InterpolationMode.Bilinear;
			graphics.PixelOffsetMode = PixelOffsetMode.Half;
			attributes.SetWrapMode(WrapMode.TileFlipXY);
			graphics.DrawImage(
				source,
				new Rectangle(0, 0, resizedWidth, InputHeight),
				0,
				0,
				source.Width,
				source.Height,
				GraphicsUnit.Pixel,
				attributes);
		}

		Rectangle bounds = new(0, 0, resized.Width, resized.Height);
		BitmapData data = resized.LockBits(bounds, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
		try
		{
			int absoluteStride = Math.Abs(data.Stride);
			byte[] bytes = new byte[checked(absoluteStride * data.Height)];
			Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);
			int planeSize = InputHeight * InputWidth;
			int batchOffset = checked(batchIndex * InputChannels * planeSize);
			for (int y = 0; y < InputHeight; y++)
			{
				int sourceRow = data.Stride >= 0 ? y * absoluteStride : (InputHeight - 1 - y) * absoluteStride;
				for (int x = 0; x < resizedWidth; x++)
				{
					int pixel = sourceRow + x * 3;
					int target = y * InputWidth + x;
					// Format24bppRgb is stored as BGR, which is PP-OCRv5's declared input order.
					destination[batchOffset + target] = bytes[pixel] / 127.5f - 1f;
					destination[batchOffset + planeSize + target] = bytes[pixel + 1] / 127.5f - 1f;
					destination[batchOffset + planeSize * 2 + target] = bytes[pixel + 2] / 127.5f - 1f;
				}
			}
		}
		finally
		{
			resized.UnlockBits(data);
		}
	}

	private static IReadOnlyList<string> LoadCharacterDictionary(ModelMetadata metadata)
	{
		if (!metadata.CustomMetadataMap.TryGetValue("character", out string? embeddedDictionary)
			|| string.IsNullOrEmpty(embeddedDictionary))
		{
			throw new InvalidDataException("The bundled PP-OCRv5 model has no embedded character dictionary.");
		}

		List<string> characters = new();
		using StringReader reader = new(embeddedDictionary);
		while (reader.ReadLine() is string line)
		{
			characters.Add(line);
		}

		if (characters.Count != CharacterDictionaryCount
			|| characters[0] != "0"
			|| characters[9] != "9"
			|| characters[10] != "A"
			|| characters.Any(string.IsNullOrEmpty)
			|| characters.Distinct(StringComparer.Ordinal).Count() != CharacterDictionaryCount)
		{
			throw new InvalidDataException("The bundled PP-OCRv5 character dictionary is incompatible with the model.");
		}
		return characters.AsReadOnly();
	}

	private static void ValidateModelContract(InferenceSession modelSession)
	{
		if (modelSession.InputMetadata.Count != 1
			|| !modelSession.InputMetadata.TryGetValue(InputName, out NodeMetadata? input)
			|| !input.IsTensor
			|| input.ElementType != typeof(float)
			|| input.Dimensions.Length != 4
			|| input.Dimensions[1] != InputChannels
			|| (input.Dimensions[2] > 0 && input.Dimensions[2] != InputHeight)
			|| modelSession.OutputMetadata.Count != 1
			|| !modelSession.OutputMetadata.TryGetValue(OutputName, out NodeMetadata? output)
			|| !output.IsTensor
			|| output.ElementType != typeof(float)
			|| output.Dimensions.Length != 3
			|| output.Dimensions[2] != OutputClassCount)
		{
			throw new InvalidDataException("The bundled PP-OCRv5 model has an unexpected input or output contract.");
		}
	}

	internal static IReadOnlyList<PpOcrv5QuantityCropVariant> CreateProductionCropVariants(
		Bitmap screenshot,
		Rectangle sourceSlot)
	{
		return new[]
		{
			CreateUnpaddedVariant("primary", screenshot, sourceSlot, 1.12),
			CreateUnpaddedVariant("raw106", screenshot, sourceSlot, 1.06),
			CreateUnpaddedVariant("raw100", screenshot, sourceSlot, 1.00),
			CreateRightVariant("right-color", screenshot, sourceSlot, RightVariantMode.Color),
			CreateRightVariant("right-gray", screenshot, sourceSlot, RightVariantMode.Grayscale),
			CreateRightVariant("right-otsu", screenshot, sourceSlot, RightVariantMode.Otsu)
		};
	}

	internal static string? NormalizeStrictQuantityToken(string? raw)
	{
		string normalized = (raw ?? string.Empty).ToUpperInvariant().Trim();
		if (SeparatorQuantityPattern.IsMatch(normalized))
		{
			char[] correctedSeparator = normalized.ToCharArray();
			correctedSeparator[normalized.Length - 3] = '.';
			normalized = new string(correctedSeparator);
		}
		if (!StrictQuantityPattern.IsMatch(normalized))
		{
			return null;
		}

		// BDO inventory stacks cannot contain zero items. Keeping zero out of the
		// valid-token domain ensures every accepted OCR guess can also be written
		// into the positive-integer quantity field.
		return ExpandConfirmedQuantity(normalized).ExactQuantity > 0 ? normalized : null;
	}

	internal static PpOcrv5QuantityDecision SelectStrictConsensus(
		Rectangle sourceSlot,
		IReadOnlyList<PpOcrv5QuantityCandidate> candidates)
	{
		if (candidates.Count != 6
			|| !candidates.Select(candidate => candidate.VariantId).ToHashSet(StringComparer.Ordinal)
				.SetEquals(new[] { "primary", "raw106", "raw100", "right-color", "right-gray", "right-otsu" }))
		{
			throw new InvalidOperationException("The production quantity decision requires the calibrated full-number and single-glyph views.");
		}
		PpOcrv5QuantityCandidate[] legacyMain = candidates
			.Where(candidate => candidate.VariantId is "primary" or "raw106" or "raw100")
			.ToArray();
		PpOcrv5QuantityCandidate[] right = candidates
			.Where(candidate => candidate.VariantId.StartsWith("right-", StringComparison.Ordinal))
			.ToArray();
		PpOcrv5QuantityCandidate best = candidates
			.OrderByDescending(candidate => candidate.NormalizedToken is not null)
			.ThenByDescending(candidate => !string.IsNullOrWhiteSpace(candidate.Text))
			.ThenByDescending(candidate => candidate.Confidence)
			.ThenBy(candidate => candidate.VariantId, StringComparer.Ordinal)
			.First();
		PpOcrv5QuantitySuggestion? suggestion = SelectQuantitySuggestion(
			legacyMain,
			"mainDirectAgreement",
			"mainDirectSingle")
			?? SelectNumericGrammarSuggestion(legacyMain)
			?? SelectQuantitySuggestion(right, "rightDirect", "rightDirect");
		double consensusMinimum = legacyMain.Min(candidate => candidate.Confidence);
		string? token = legacyMain[0].NormalizedToken;
		bool exactConsensus = token is not null
			&& legacyMain.All(candidate => string.Equals(candidate.NormalizedToken, token, StringComparison.Ordinal));
		int slotSize = Math.Min(sourceSlot.Width, sourceSlot.Height);
		if (slotSize < MinimumReliableSlotSize)
		{
			return ReviewDecision(
				best,
				consensusMinimum,
				PpOcrv5QuantityReadStatus.ReviewBelowResolution,
				"The source slot is below 45 pixels, so this quantity must be reviewed.",
				suggestion);
		}
		if (sourceSlot.X < RoundScaled(slotSize, RequiredLeftContextRatio))
		{
			return ReviewDecision(
				best,
				consensusMinimum,
				PpOcrv5QuantityReadStatus.ReviewClippedLeft,
				"The screenshot may clip a leading quantity digit, so this quantity must be reviewed.",
				suggestion);
		}
		if (!exactConsensus)
		{
			bool anyValidMain = legacyMain.Any(candidate => candidate.NormalizedToken is not null);
			if (!anyValidMain)
			{
				string? rightToken = right[0].NormalizedToken;
				bool rightConsensus = rightToken is { Length: 1 }
					&& rightToken[0] is >= '0' and <= '9'
					&& right.All(candidate => string.Equals(candidate.NormalizedToken, rightToken, StringComparison.Ordinal));
				double rightMinimum = right.Min(candidate => candidate.Confidence);
				if (rightConsensus && rightMinimum >= SingleGlyphConsensusConfidenceFloor)
				{
					(int rescuedQuantity, bool rescuedRounded) = ExpandConfirmedQuantity(rightToken!);
					PpOcrv5QuantityCandidate rightBest = right
						.OrderByDescending(candidate => candidate.Confidence)
						.ThenBy(candidate => candidate.VariantId, StringComparer.Ordinal)
						.First();
					return new PpOcrv5QuantityDecision(
						rightBest.Text,
						rightToken,
						rescuedQuantity,
						rescuedRounded,
						rightMinimum,
						PpOcrv5QuantityReadStatus.Confirmed,
						string.Empty,
						"right-3of3");
				}
			}
			bool anyValidGuess = suggestion is not null
				|| candidates.Any(candidate => candidate.NormalizedToken is not null);
			return ReviewDecision(
				best,
				consensusMinimum,
				anyValidGuess ? PpOcrv5QuantityReadStatus.ReviewLowConsensus : PpOcrv5QuantityReadStatus.Invalid,
				anyValidGuess
					? "The OCR views did not agree exactly, so this quantity must be reviewed."
					: "No complete quantity token was read, so this quantity must be reviewed.",
				suggestion);
		}
		if (consensusMinimum < MainConsensusConfidenceFloor)
		{
			return ReviewDecision(
				best,
				consensusMinimum,
				PpOcrv5QuantityReadStatus.ReviewLowConfidence,
				"The OCR views agree, but the read is not clear enough to import automatically.",
				suggestion);
		}

		(int exactQuantity, bool isRounded) = ExpandConfirmedQuantity(token!);
		return new PpOcrv5QuantityDecision(
			best.Text,
			token,
			exactQuantity,
			isRounded,
			consensusMinimum,
			PpOcrv5QuantityReadStatus.Confirmed,
			string.Empty,
			"main-3of3");
	}

	private static PpOcrv5QuantityCropVariant CreateUnpaddedVariant(
		string id,
		Bitmap screenshot,
		Rectangle sourceSlot,
		double rightRatio)
	{
		int slotSize = Math.Min(sourceSlot.Width, sourceSlot.Height);
		int left = Math.Clamp(sourceSlot.X + RoundScaled(slotSize, -0.24), 0, screenshot.Width);
		int right = Math.Clamp(sourceSlot.X + RoundScaled(slotSize, rightRatio), 0, screenshot.Width);
		int top = Math.Clamp(sourceSlot.Y + RoundScaled(slotSize, 0.57), 0, screenshot.Height);
		int bottom = Math.Clamp(sourceSlot.Y + RoundScaled(slotSize, 0.99), 0, screenshot.Height);
		if (right <= left || bottom <= top)
		{
			throw new InvalidOperationException("The detected source slot cannot produce a non-empty quantity view.");
		}
		return new PpOcrv5QuantityCropVariant(
			id,
			screenshot.Clone(Rectangle.FromLTRB(left, top, right, bottom), PixelFormat.Format24bppRgb));
	}

	private static PpOcrv5QuantityCropVariant CreateRightVariant(
		string id,
		Bitmap screenshot,
		Rectangle sourceSlot,
		RightVariantMode mode)
	{
		int slotSize = Math.Min(sourceSlot.Width, sourceSlot.Height);
		int left = Math.Clamp(sourceSlot.X + RoundScaled(slotSize, 0.35), 0, screenshot.Width);
		int right = Math.Clamp(sourceSlot.X + RoundScaled(slotSize, 1.00), 0, screenshot.Width);
		int top = Math.Clamp(sourceSlot.Y + RoundScaled(slotSize, 0.45), 0, screenshot.Height);
		int bottom = Math.Clamp(sourceSlot.Y + RoundScaled(slotSize, 1.00), 0, screenshot.Height);
		if (right <= left || bottom <= top)
		{
			throw new InvalidOperationException("The detected source slot cannot produce a single-glyph quantity view.");
		}

		Bitmap image = screenshot.Clone(Rectangle.FromLTRB(left, top, right, bottom), PixelFormat.Format24bppRgb);
		if (mode != RightVariantMode.Color)
		{
			ConvertRightVariant(image, mode == RightVariantMode.Otsu);
		}
		return new PpOcrv5QuantityCropVariant(id, image);
	}

	private static void ConvertRightVariant(Bitmap image, bool applyOtsu)
	{
		int[] histogram = new int[256];
		byte[] luminance = new byte[checked(image.Width * image.Height)];
		for (int y = 0; y < image.Height; y++)
		{
			for (int x = 0; x < image.Width; x++)
			{
				Color color = image.GetPixel(x, y);
				byte value = (byte)Math.Clamp((int)Math.Round(color.R * 0.299 + color.G * 0.587 + color.B * 0.114), 0, 255);
				luminance[y * image.Width + x] = value;
				histogram[value]++;
			}
		}

		int threshold = applyOtsu ? CalculateOtsuThreshold(histogram, luminance.Length) : -1;
		for (int y = 0; y < image.Height; y++)
		{
			for (int x = 0; x < image.Width; x++)
			{
				int value = luminance[y * image.Width + x];
				if (applyOtsu)
				{
					value = value > threshold ? 255 : 0;
				}
				image.SetPixel(x, y, Color.FromArgb(value, value, value));
			}
		}
	}

	private static int CalculateOtsuThreshold(IReadOnlyList<int> histogram, int total)
	{
		long weightedTotal = 0;
		for (int value = 0; value < histogram.Count; value++)
		{
			weightedTotal += (long)value * histogram[value];
		}

		long backgroundWeight = 0;
		long backgroundSum = 0;
		double maximumVariance = -1;
		int bestThreshold = 0;
		for (int threshold = 0; threshold < histogram.Count; threshold++)
		{
			backgroundWeight += histogram[threshold];
			if (backgroundWeight == 0)
			{
				continue;
			}
			long foregroundWeight = total - backgroundWeight;
			if (foregroundWeight == 0)
			{
				break;
			}
			backgroundSum += (long)threshold * histogram[threshold];
			double backgroundMean = backgroundSum / (double)backgroundWeight;
			double foregroundMean = (weightedTotal - backgroundSum) / (double)foregroundWeight;
			double difference = backgroundMean - foregroundMean;
			double variance = backgroundWeight * (double)foregroundWeight * difference * difference;
			if (variance > maximumVariance)
			{
				maximumVariance = variance;
				bestThreshold = threshold;
			}
		}
		return bestThreshold;
	}

	private static int RoundScaled(int value, double ratio)
	{
		return checked((int)Math.Round(value * ratio, MidpointRounding.ToEven));
	}

	private static (int ExactQuantity, bool IsRounded) ExpandConfirmedQuantity(string token)
	{
		if (token[^1] is not ('K' or 'M'))
		{
			return (int.Parse(token, NumberStyles.None, CultureInfo.InvariantCulture), false);
		}
		int multiplier = token[^1] == 'K' ? 1_000 : 1_000_000;
		int separator = token.IndexOf('.');
		int whole = int.Parse(token.AsSpan(0, separator), NumberStyles.None, CultureInfo.InvariantCulture);
		int tenth = token[separator + 1] - '0';
		return (checked(whole * multiplier + tenth * (multiplier / 10)), true);
	}

	private static PpOcrv5QuantitySuggestion? SelectQuantitySuggestion(
		IReadOnlyList<PpOcrv5QuantityCandidate> candidates,
		string agreementEvidence,
		string singleEvidence)
	{
		PpOcrv5QuantityCandidate[] valid = candidates
			.Where(candidate => candidate.NormalizedToken is not null)
			.ToArray();
		if (valid.Length == 0)
		{
			return null;
		}

		IGrouping<string, PpOcrv5QuantityCandidate>? majority = valid
			.GroupBy(candidate => candidate.NormalizedToken!, StringComparer.Ordinal)
			.Where(group => group.Count() >= 2)
			.OrderByDescending(group => group.Count())
			.ThenByDescending(group => group.Max(candidate => candidate.Confidence))
			.ThenBy(group => group.Key, StringComparer.Ordinal)
			.FirstOrDefault();
		if (majority is not null)
		{
			return CreateQuantitySuggestion(
				majority.Key,
				agreementEvidence,
				majority.Count(),
				majority.Min(candidate => candidate.Confidence));
		}
		PpOcrv5QuantityCandidate winner = valid
			.OrderByDescending(candidate => candidate.Confidence)
			.ThenBy(candidate => candidate.VariantId, StringComparer.Ordinal)
			.First();
		return CreateQuantitySuggestion(
			winner.NormalizedToken,
			singleEvidence,
			1,
			winner.Confidence);
	}

	private static PpOcrv5QuantitySuggestion? SelectNumericGrammarSuggestion(
		IReadOnlyList<PpOcrv5QuantityCandidate> candidates)
	{
		IGrouping<string, PpOcrv5QuantityCandidate>? winner = candidates
			.Where(candidate =>
				candidate.NumericToken is not null
				&& candidate.NumericPosterior >= NumericSuggestionPosteriorFloor
				&& (double.IsPositiveInfinity(candidate.NumericLogMargin)
					|| candidate.NumericLogMargin >= NumericSuggestionMarginFloor)
				&& candidate.Confidence >= NumericSuggestionRawConfidenceFloor
				&& SupportsGrammarRecovery(candidate))
			.GroupBy(candidate => candidate.NumericToken!, StringComparer.Ordinal)
			.Where(group => group.Count() >= NumericSuggestionMinimumViewAgreement)
			.OrderByDescending(group => group.Count())
			.ThenByDescending(group => group.Min(candidate => candidate.NumericPosterior))
			.ThenByDescending(group => group.Min(candidate => candidate.NumericLogMargin))
			.ThenBy(group => group.Key, StringComparer.Ordinal)
			.FirstOrDefault();
		return winner is null
			? null
			: CreateQuantitySuggestion(
				winner.Key,
				"mainNumericGrammar",
				winner.Count(),
				winner.Min(candidate => candidate.Confidence));
	}

	private static bool SupportsGrammarRecovery(PpOcrv5QuantityCandidate candidate)
	{
		string? token = candidate.NumericToken;
		if (token is null)
		{
			return false;
		}
		string raw = candidate.Text.Trim().ToUpperInvariant()
			.Replace(',', '.')
			.Replace(':', '.');
		if (!raw.Any(character => character is >= '0' and <= '9'))
		{
			return false;
		}

		char? rawSuffix = raw.Length > 0 && raw[^1] is 'K' or 'M' ? raw[^1] : null;
		char? tokenSuffix = token[^1] is 'K' or 'M' ? token[^1] : null;
		if (rawSuffix != tokenSuffix)
		{
			return false;
		}
		return EditDistanceAtMostOne(raw, token);
	}

	private static bool EditDistanceAtMostOne(string left, string right)
	{
		if (Math.Abs(left.Length - right.Length) > 1)
		{
			return false;
		}
		int leftIndex = 0;
		int rightIndex = 0;
		int edits = 0;
		while (leftIndex < left.Length && rightIndex < right.Length)
		{
			if (left[leftIndex] == right[rightIndex])
			{
				leftIndex++;
				rightIndex++;
				continue;
			}
			if (++edits > 1)
			{
				return false;
			}
			if (left.Length > right.Length)
			{
				leftIndex++;
			}
			else if (right.Length > left.Length)
			{
				rightIndex++;
			}
			else
			{
				leftIndex++;
				rightIndex++;
			}
		}
		if (leftIndex < left.Length || rightIndex < right.Length)
		{
			edits++;
		}
		return edits <= 1;
	}

	private static PpOcrv5QuantitySuggestion? CreateQuantitySuggestion(
		string? token,
		string evidence,
		int agreementCount,
		double supportingMinConfidence)
	{
		if (token is null)
		{
			return null;
		}

		(int quantity, bool rounded) = ExpandConfirmedQuantity(token);
		return new PpOcrv5QuantitySuggestion(
			token,
			quantity,
			rounded,
			evidence,
			agreementCount,
			Math.Clamp(supportingMinConfidence, 0, 1));
	}

	private static PpOcrv5QuantityDecision ReviewDecision(
		PpOcrv5QuantityCandidate best,
		double consensusMinimum,
		PpOcrv5QuantityReadStatus status,
		string reviewMessage,
		PpOcrv5QuantitySuggestion? suggestion)
	{
		return new PpOcrv5QuantityDecision(
			best.Text,
			null,
			null,
			false,
			consensusMinimum,
			status,
			reviewMessage,
			null,
			suggestion);
	}

	public void Dispose()
	{
		if (disposed)
		{
			return;
		}
		disposed = true;
		session.Dispose();
	}

	private sealed record PendingVariant(int SourceIndex, PpOcrv5QuantityCropVariant Variant);
	private readonly record struct NumericCtcClass(int ClassIndex, char Character);
	private readonly record struct NumericCtcBeam(
		double BlankLogProbability,
		double NonBlankLogProbability)
	{
		internal static NumericCtcBeam Empty => new(
			double.NegativeInfinity,
			double.NegativeInfinity);
	}
	private readonly record struct PpOcrv5NumericCandidate(
		string? Token,
		double Posterior,
		double LogMargin)
	{
		internal static PpOcrv5NumericCandidate Empty => new(null, 0, 0);
	}
	private enum RightVariantMode
	{
		Color,
		Grayscale,
		Otsu
	}
}

internal delegate IReadOnlyList<PpOcrv5QuantityCropVariant> PpOcrv5QuantityCropVariantFactory(
	Bitmap screenshot,
	Rectangle crop);

internal delegate PpOcrv5QuantityDecision PpOcrv5QuantityCandidateRanker(
	Rectangle sourceSlot,
	IReadOnlyList<PpOcrv5QuantityCandidate> candidates);

internal sealed class PpOcrv5QuantityCropVariant : IDisposable
{
	internal PpOcrv5QuantityCropVariant(string id, Bitmap image)
	{
		Id = id;
		Image = image ?? throw new ArgumentNullException(nameof(image));
	}

	internal string Id { get; }
	internal Bitmap Image { get; }

	public void Dispose()
	{
		Image.Dispose();
	}
}

internal sealed record PpOcrv5QuantityCandidate(
	string VariantId,
	string Text,
	double Confidence,
	double MinimumCharacterConfidence,
	string? NormalizedToken,
	string? NumericToken,
	double NumericPosterior,
	double NumericLogMargin);

internal sealed record PpOcrv5QuantityDecision(
	string RawBest,
	string? ConfirmedToken,
	int? ExactQuantity,
	bool IsRounded,
	double ConsensusMinConfidence,
	PpOcrv5QuantityReadStatus Status,
	string ReviewMessage,
	string? ConfirmationRule,
	PpOcrv5QuantitySuggestion? Suggestion = null);

internal sealed record PpOcrv5QuantitySuggestion(
	string Token,
	int Quantity,
	bool IsRounded,
	string Evidence,
	int AgreementCount,
	double SupportingMinConfidence);

internal enum PpOcrv5QuantityReadStatus
{
	Confirmed,
	ReviewLowConsensus,
	ReviewLowConfidence,
	ReviewBelowResolution,
	ReviewClippedLeft,
	Invalid
}

internal sealed record PpOcrv5QuantityRecognition(
	Rectangle SourceBounds,
	PpOcrv5QuantityDecision Decision,
	IReadOnlyList<PpOcrv5QuantityCandidate> Candidates);
