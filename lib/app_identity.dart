/// Stable identity values for the Black Spirit Life public application.
///
/// The portable planner document marker intentionally remains
/// `BDO Craft Planner`; it describes the compatible document format rather
/// than the installed application's writable identity.
abstract final class AppIdentity {
  static const baseProductName = 'Black Spirit Life';
  static const productName = 'Black Spirit Life';
  static const displayName = productName;
  static const releaseChannel = 'win-x64-stable';
  static const applicationVersion = '0.1.13';

  /// About remains implemented and verified, but its navigation entry stays
  /// hidden until a later product update explicitly enables it.
  static const showAboutDestination = false;

  /// Regular installations use schema-based one-time setup. An application
  /// update does not reopen already completed setup questions.
  static const repeatFullSetupEveryApplicationVersion = false;

  /// A public installation always creates its own clean personal profile.
  /// Older Beta/Avalonia data remains untouched and can only be brought in by
  /// an explicit user-driven import flow after setup.
  static const importFormerProfilesOnFirstLaunch = false;

  /// Installed Beta 3 exposed native heap corruption during an in-process
  /// Velopack update check. Keep updater operations outside the planner until
  /// they have been isolated and verified against an installed profile.
  static const inProcessBetaUpdatesEnabled = false;

  /// Manager/check/download/apply work runs in a disposable helper process,
  /// so a native updater fault cannot terminate the planner.
  static const outOfProcessBetaUpdatesEnabled = true;

  /// Session-unlocked Editor Settings preview of the title-bar update button.
  /// It never contacts the feed, downloads, installs or restarts.
  static const developerUpdateTestEnabled = true;

  /// Permanent Velopack ownership identity for the public application.
  /// This must remain distinct from every settings and cache directory name.
  static const installerPackageId = 'BlackSpiritLife.App';
  static const stableInstallerPackageId = installerPackageId;
  static const liveBetaInstallerPackageId = 'BlackSpiritLife.App.LiveBeta';
  static const formerInstallerPackageId = 'BlackSpiritLife.App.Beta';

  /// Writable identities remain explicit so prior test builds can coexist.
  static const stateDirectoryName = 'Black Spirit Life';
  static const stableStateDirectoryName = 'Black Spirit Life';
  static const liveBetaStateDirectoryName = 'Black Spirit Life Live Beta';
  static const localCacheDirectoryName = 'Black Spirit Life';
  static const stableLocalCacheDirectoryName = 'Black Spirit Life';
  static const liveBetaLocalCacheDirectoryName = 'Black Spirit Life Live Beta';
  static const formerLocalCacheDirectoryName = 'Black Spirit Life Beta';

  /// Non-personal marker left after an explicitly requested uninstall wipe.
  /// It prevents an untouched legacy profile from silently repopulating the
  /// next fresh installation.
  static const intentionalResetMarkerFileName =
      '.black-spirit-life-intentional-reset.json';

  /// Former test identity kept only for separation and path protection. The
  /// public application never imports it automatically.
  static const formerStateDirectoryName = 'Black Spirit Life Beta';

  static const windowsExecutableName = 'BlackSpiritLife.exe';
  static const windowsUpdaterHelperName = 'BlackSpiritLifeUpdater.exe';
  static const appIconAssetPath = 'assets/app/black_spirit_life_icon.png';
}
