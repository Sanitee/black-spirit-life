# Installer location and missing-registration repair

This installer-only change is based on the published 0.1.10 application. It does
not change the Flutter app, update packages, reference assets or user-data
storage. Public distribution remains the responsibility of the Live Release
owner; preparing this fix does not replace an existing public release asset.

## Behavior

- Fresh installation suggests `C:\Black Spirit Life`. The user can type a
  destination or use Browse; setup creates a missing named destination when
  installation begins. An unwritable destination reports an error and remains
  editable. This does not introduce elevation or Program Files support.
- A verified existing installation keeps its registered location for update or
  repair. It is not silently relocated to the new suggested destination.
- A registered destination that is positively absent on a reachable fixed drive
  offers a Reinstall screen. Confirmation names the missing folder and the chosen
  new location. Discovery and cancellation never remove registration or saved
  state. The existing setup engine registers the chosen installation.
- Access failures, redirected paths, malformed registrations and conflicting
  installations are not treated as proof that an installation has disappeared.
- Fresh/recovery state is revalidated before setup launches. A changed
  registration or incompatible reappearing installation stops the attempt.
- Pre-launch failure may remove only the still-empty final directory created
  by that attempt, using its verified handle. No recursive cleanup, existing
  directory removal, or personal-data cleanup is introduced. After setup starts,
  its output is preserved for normal failure diagnosis.

## Verification and limits

The native regression suite uses injected read-only discovery dependencies,
temporary filesystem fixtures and model assertions. It must not overwrite the
real Windows uninstall registration to simulate a missing installation.

Build the standalone installer and `BlackSpiritLifeInstallerNativeTests` target
from `windows/installer`, run CTest, and verify `--verify-payload` against the
sealed setup engine used for the application version. Capture fresh and recovery
screens with `--capture-preview`; `--preview-missing-install` is a rendering-only
fixture argument and cannot bypass real startup discovery.

Before a public installer release, the owner must also exercise the exact final
installer against isolated fresh/stale-registration/existing-installation states
and verify the installed payload, selected path and preserved personal data.
Unit/model tests and preview captures alone are not an installed lifecycle pass.
Use a separate Windows test account/VM for real setup registration tests rather
than replacing the user's active HKCU installation entry.
