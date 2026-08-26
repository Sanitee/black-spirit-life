using System;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace BlackSpiritHub;

internal static class Program
{
	private const int FailureExitCode = 2;
	private const int NativeTimeoutSeconds = 90;
	private const int MaximumJsonOverheadCharacters = 4096;
	private const int MaximumErrorCharacters = 512;
	private const string ServerArgument = "--server";
	private const string WarmCommand = "WARM";
	private static readonly JsonSerializerOptions ResponseJsonOptions = new()
	{
		PropertyNamingPolicy = JsonNamingPolicy.CamelCase
	};

	private static async Task<int> Main(string[] args)
	{
		if (args.Length == 2 && string.Equals(args[0], "--fixture", StringComparison.Ordinal))
		{
			return RecipeBookOcrFixtureRunner.Run(AppContext.BaseDirectory, args[1]);
		}
		if (args.Length == 1 && string.Equals(args[0], ServerArgument, StringComparison.Ordinal))
		{
			return await RunServerAsync().ConfigureAwait(false);
		}

		if (args.Length != 0)
		{
			WriteBoundedError("Usage: BlackSpiritStorageOcr.exe [--server | --fixture <manifest.json>]");
			return FailureExitCode;
		}

		using CancellationTokenSource cancellation = new(TimeSpan.FromSeconds(NativeTimeoutSeconds));
		ConsoleCancelEventHandler cancelHandler = (_, eventArgs) =>
		{
			eventArgs.Cancel = true;
			cancellation.Cancel();
		};
		Console.CancelKeyPress += cancelHandler;
		try
		{
			string requestJson = await ReadBoundedStandardInputAsync(cancellation.Token).ConfigureAwait(false);
			using JsonDocument document = JsonDocument.Parse(
				requestJson,
				new JsonDocumentOptions
				{
					AllowTrailingCommas = false,
					CommentHandling = JsonCommentHandling.Disallow,
					MaxDepth = 8
				});
			RecipeBookScreenshotRequest request = RecipeBookScreenshotService.ParsePayload(document.RootElement);
			using RecipeBookScreenshotService service = new(AppContext.BaseDirectory);
			RecipeBookScreenshotResult result = await service.AnalyzeAsync(request, cancellation.Token).ConfigureAwait(false);
			await Console.Out.WriteAsync(JsonSerializer.Serialize(result, ResponseJsonOptions)).ConfigureAwait(false);
			return 0;
		}
		catch (OperationCanceledException)
		{
			WriteBoundedError("Storage screenshot recognition was cancelled or exceeded 90 seconds.");
			return FailureExitCode;
		}
		catch (Exception exception) when (exception is ArgumentException
			or InvalidDataException
			or InvalidOperationException
			or JsonException
			or IOException
			or UnauthorizedAccessException)
		{
			WriteBoundedError(exception.Message);
			return FailureExitCode;
		}
		catch (Exception)
		{
			WriteBoundedError("Storage screenshot recognition failed unexpectedly.");
			return FailureExitCode;
		}
		finally
		{
			Console.CancelKeyPress -= cancelHandler;
		}
	}

	private static async Task<int> RunServerAsync()
	{
		using CancellationTokenSource lifetime = new();
		ConsoleCancelEventHandler cancelHandler = (_, eventArgs) =>
		{
			eventArgs.Cancel = true;
			lifetime.Cancel();
		};
		Console.CancelKeyPress += cancelHandler;
		try
		{
			using RecipeBookScreenshotService service = new(AppContext.BaseDirectory);
			await Console.Out.WriteLineAsync("READY\t1").ConfigureAwait(false);
			await Console.Out.FlushAsync().ConfigureAwait(false);

			while (!lifetime.IsCancellationRequested)
			{
				string? requestLine;
				try
				{
					requestLine = await Console.In.ReadLineAsync(lifetime.Token).ConfigureAwait(false);
				}
				catch (OperationCanceledException) when (lifetime.IsCancellationRequested)
				{
					break;
				}
				if (requestLine is null)
				{
					break;
				}
				if (requestLine.Length == 0)
				{
					continue;
				}

				int separator = requestLine.IndexOf('\t');
				if (separator <= 0 || !int.TryParse(requestLine.AsSpan(0, separator), out int requestId))
				{
					await WriteServerErrorAsync(0, "The storage screenshot request ID is invalid.").ConfigureAwait(false);
					continue;
				}
				string requestPayload = requestLine[(separator + 1)..];
				int maximumCharacters = checked(
					RecipeBookScreenshotService.MaxEncodedCharacters + MaximumJsonOverheadCharacters);
				if (requestPayload.Length == 0 || requestPayload.Length > maximumCharacters)
				{
					await WriteServerErrorAsync(requestId, "The screenshot request is too large.").ConfigureAwait(false);
					continue;
				}

				bool isWarmRequest = string.Equals(requestPayload, WarmCommand, StringComparison.Ordinal);
				try
				{
					using CancellationTokenSource requestCancellation =
						CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
					requestCancellation.CancelAfter(TimeSpan.FromSeconds(NativeTimeoutSeconds));
					if (isWarmRequest)
					{
						await service.WarmAsync(requestCancellation.Token).ConfigureAwait(false);
						await WriteServerSuccessAsync(requestId, WarmCommand).ConfigureAwait(false);
						continue;
					}

					using JsonDocument document = JsonDocument.Parse(
						requestPayload,
						new JsonDocumentOptions
						{
							AllowTrailingCommas = false,
							CommentHandling = JsonCommentHandling.Disallow,
							MaxDepth = 8
						});
					RecipeBookScreenshotRequest request = RecipeBookScreenshotService.ParsePayload(document.RootElement);
					RecipeBookScreenshotResult result = await service
						.AnalyzeAsync(request, requestCancellation.Token)
						.ConfigureAwait(false);
					await WriteServerSuccessAsync(
						requestId,
						JsonSerializer.Serialize(result, ResponseJsonOptions)).ConfigureAwait(false);
				}
				catch (OperationCanceledException) when (!lifetime.IsCancellationRequested)
				{
					await WriteServerErrorAsync(
						requestId,
						isWarmRequest
							? "Storage screenshot recognizer warm-up exceeded 90 seconds."
							: "Storage screenshot recognition exceeded 90 seconds.").ConfigureAwait(false);
				}
				catch (Exception exception) when (exception is ArgumentException
					or InvalidDataException
					or InvalidOperationException
					or JsonException
					or IOException
					or UnauthorizedAccessException)
				{
					await WriteServerErrorAsync(requestId, exception.Message).ConfigureAwait(false);
				}
				catch (Exception)
				{
					await WriteServerErrorAsync(
						requestId,
						"Storage screenshot recognition failed unexpectedly.").ConfigureAwait(false);
				}
			}
			return 0;
		}
		catch (OperationCanceledException)
		{
			return 0;
		}
		catch (Exception exception) when (exception is ArgumentException
			or InvalidDataException
			or InvalidOperationException
			or JsonException
			or IOException
			or UnauthorizedAccessException)
		{
			WriteBoundedError(exception.Message);
			return FailureExitCode;
		}
		catch (Exception)
		{
			WriteBoundedError("Storage screenshot recognition failed unexpectedly.");
			return FailureExitCode;
		}
		finally
		{
			Console.CancelKeyPress -= cancelHandler;
		}
	}

	private static async Task WriteServerSuccessAsync(int requestId, string payload)
	{
		await Console.Out.WriteAsync($"OK\t{requestId}\t").ConfigureAwait(false);
		await Console.Out.WriteLineAsync(payload).ConfigureAwait(false);
		await Console.Out.FlushAsync().ConfigureAwait(false);
	}

	private static async Task WriteServerErrorAsync(int requestId, string message)
	{
		await Console.Out.WriteLineAsync(
			$"ERR\t{requestId}\t{NormalizeBoundedError(message)}").ConfigureAwait(false);
		await Console.Out.FlushAsync().ConfigureAwait(false);
	}

	private static async Task<string> ReadBoundedStandardInputAsync(CancellationToken cancellationToken)
	{
		int maximumCharacters = checked(
			RecipeBookScreenshotService.MaxEncodedCharacters + MaximumJsonOverheadCharacters);
		char[] buffer = new char[8192];
		StringBuilder input = new(Math.Min(maximumCharacters, 64 * 1024));
		while (true)
		{
			int read = await Console.In.ReadAsync(buffer.AsMemory(), cancellationToken).ConfigureAwait(false);
			if (read == 0)
			{
				break;
			}

			if (input.Length > maximumCharacters - read)
			{
				throw new InvalidDataException("The screenshot request is too large.");
			}
			input.Append(buffer, 0, read);
		}

		if (input.Length == 0)
		{
			throw new InvalidDataException("A screenshot request is required on standard input.");
		}
		return input.ToString();
	}

	private static void WriteBoundedError(string message)
	{
		Console.Error.WriteLine(NormalizeBoundedError(message));
	}

	private static string NormalizeBoundedError(string message)
	{
		string normalized = string.IsNullOrWhiteSpace(message)
			? "Storage screenshot recognition failed."
			: message.Replace('\r', ' ').Replace('\n', ' ').Trim();
		if (normalized.Length > MaximumErrorCharacters)
		{
			normalized = normalized[..MaximumErrorCharacters];
		}
		return normalized;
	}
}
