namespace BlackSpiritLife.SessionImport.SummaryOcr;

public interface ISummaryOcrReader
{
    Task<SummaryOcrResult> ReadAsync(
        string imagePath,
        CancellationToken cancellationToken = default);

    Task<SummaryOcrResult> ReadAsync(
        Stream imageStream,
        CancellationToken cancellationToken = default);
}
