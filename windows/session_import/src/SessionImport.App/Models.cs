using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;

namespace BlackSpiritLife.SessionImport.App;

public sealed record SpotChoice(string Name, string SpotId, string Activity)
{
    public override string ToString() => Name;
}

public sealed class LootRowViewModel : INotifyPropertyChanged
{
    private string _name;
    private string _quantity;
    private string? _iconPath;

    public LootRowViewModel(string name, long quantity, string? itemId = null, string? iconPath = null)
    {
        _name = name;
        _quantity = quantity.ToString("N0");
        ItemId = itemId;
        _iconPath = iconPath;
    }

    public string Name
    {
        get => _name;
        set { if (_name == value) return; _name = value; OnPropertyChanged(); }
    }

    public string Quantity
    {
        get => _quantity;
        set { if (_quantity == value) return; _quantity = value; OnPropertyChanged(); }
    }

    public string? ItemId { get; set; }

    public string? IconPath
    {
        get => _iconPath;
        set
        {
            if (_iconPath == value) return;
            _iconPath = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(PlaceholderVisibility));
        }
    }

    public Visibility PlaceholderVisibility => string.IsNullOrWhiteSpace(IconPath)
        ? Visibility.Visible
        : Visibility.Collapsed;

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
