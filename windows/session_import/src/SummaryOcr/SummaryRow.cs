namespace BlackSpiritLife.SessionImport.SummaryOcr;

public sealed record SummaryRow(string ItemName, long Count);

public sealed record SummaryOcrResult(
    IReadOnlyList<SummaryRow> Rows,
    string RawText,
    IReadOnlyList<string> Warnings);
