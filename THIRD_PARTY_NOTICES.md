# Third-party notices

Black Spirit Life is a free, noncommercial, unofficial fan tool.

> This is unofficial content which contains copyrighted materials and IP from Pearl Abyss, and is not official/endorsed content.

The root `LICENSE` applies only to original Black Spirit Life source code. It
does not grant rights in the game artwork, game data, fan-site material, or
other third-party content listed below. This file records provenance and
release status; it is not legal advice and does not itself grant permission.

## Pearl Abyss / Black Desert

Black Desert names, item and NPC identities, item icons, NPC portraits, and
game-derived data and imagery are associated with Pearl Abyss. The project is
being prepared under Pearl Abyss's published Fan Content Guidelines as a
personal, free, noncommercial fan project. The required unofficial-content
notice appears above, in the README, and in the release notes. It is also
retained in the application About-screen implementation, whose navigation is
intentionally hidden until the project owner enables it in a later update.

The guidelines also require respect for third-party rights. They therefore do
not, by themselves, settle whether material copied from a fan database or map
provider may be redistributed. The source-by-source decision record is
`docs/public-release-source-matrix.md`.

Official policy source:

- <https://www.pearlabyss.com/en-US/legal/detail?_policyNo=42>

Contact named by the reviewed policy for uncertain fan-content uses:
`fancontent@pearlabysscorp.com`.

The Windows storage-screenshot OCR helper includes a sealed Recipe Book
snapshot with 3,897 Pearl Abyss-origin item icons plus two generated
recognition atlases. These assets are used only for local, review-first item
recognition; screenshots remain on the user's computer. The helper-specific
asset notice is distributed at
`windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook/NOTICE.txt`.

The Opportunities workspace includes 154 unmodified item icons extracted
from the owner's installed Black Desert PC client. Its public provenance file
records only client-relative asset paths, byte sizes and SHA-256 hashes. The
Resource Map also includes reviewed house-use, navigation and bare-hands
interaction textures with source notices beside those assets. No local client
path, extractor executable, account data or game installation is distributed.

## FishyStuff and Fishing reference material

Fish Map includes the reviewed reference snapshot used by the approved Beta:
FishyStuff map/API/Dex response data, derived map files, region imagery,
FishyStuff branding, node-marker images, and a catalog of PA-origin fish/item
recognition artwork delivered through FishyStuff or BDO Codex. FishyStuff is
credited and linked visibly from Fish Map.

- FishyStuff: <https://fishystuff.fish/map/>
- FishyStuff Dex: <https://fishystuff.fish/dex/>
- Exact recognition-image URLs and hashes:
  `packages/bdo_fishing_core/assets/fish_companion/recognizer/reference-icons/catalog.json`

Black Spirit Life does not claim that public availability or attribution is a
licence, and no separate FishyStuff redistribution licence or written
permission is documented. The project owner expressly approved retaining this
credited material for the free, noncommercial release and accepts the residual
risk. Pearl Abyss remains the owner of the underlying Black Desert item art.
Corrections or removal requests can use the route at the end of this file.

The immutable Fishing snapshot is not personal data. Every Fishing profile,
mastery value, haul, journal entry, sale, note, and runtime SQLite database is
created only beneath the user's selected local personal-data folder. No
publisher database or user record is included in the source or installer.

## Gathering creators, Bairog, and BDO Workshop

The Gathering companion retains the approved Beta's credited calculator facts,
20-route benchmark set, guide links, and Bairog/BDO Workshop source logo. It
also includes eleven credited guide images: four official Pearl Abyss update
illustrations and references attributed to MMOSUMO/alext96, GrumpyG, Saarith,
and bunnygirl. Exact URLs, dates, hashes, limitations, and creator names are in
`packages/bdo_gathering_companion/assets/rotations/NOTICE.md` and
`provenance.json`.

- Bairog / BDO Workshop gathering calculator:
  <https://bdoworkshop.com/gathering-calculator>
- Creator and image inventory:
  `packages/bdo_gathering_companion/assets/rotations/NOTICE.md`

No separate redistribution licence or written creator permission is claimed
for the credited community material. The project owner approved its inclusion
in this free, noncommercial release with the credits and source links intact.
Four full-frame guide captures that exposed real player/browser context are
not redistributed; the corresponding public guide links and credits remain.

## Garmoth and Session Import

Session Import retains the approved app-managed Garmoth workflow, a reviewed
snapshot of public sidebar names, numeric site IDs and supported session
columns, the Garmoth site icon, and PA-origin static item/spot art. The catalog
records its public page patterns and describes its limits; it does not contain
an account path, login, credential, cookie, or saved player session.

- Garmoth: <https://garmoth.com/>
- Catalog provenance is embedded in
  `windows/session_import/src/SessionImport.App/Assets/garmoth_spot_catalog.json`.

No Garmoth licence or written permission is claimed. The project owner
approved the credited integration/reference snapshot for the free,
noncommercial release. Any login, cookies, generated browser profile, drafts,
receipts, and imported session history remain local to the user's selected
personal-data folder and are never bundled in a release.

Fish Map uses the vendored `webview_flutter_windows` fork; Session Import uses
the Microsoft.Web.WebView2 package directly. The fork's BSD-3-Clause licence
and local-change notice remain in its package. The Microsoft runtime is
supplied by Windows/the user's installation, and generated browser profiles
are not part of the installer.

## Black Spirit Hub shared OCR source

The Windows-only `BlackSpiritStorageOcr` recognition implementation and frozen
Recipe Book snapshot were copied from Black Spirit Hub v0.9.52 at commit
`6ccbad52d25b54d8b67065ce8a9eb1bcece87d9f`. The project owner states that the
Black Spirit Hub owner shared this implementation for reuse in Black Spirit
Life. The upstream repository has no top-level software license, so that
owner-authorized reuse is recorded as project-specific permission and is not
represented as a general license grant to third parties.

The complete provenance and permission statement is distributed at
`windows/storage_ocr/BlackSpiritStorageOcr/SOURCE-NOTICE.txt`.

## PaddleOCR and ONNX Runtime

Local screenshot quantity recognition uses the RapidOCR 3.9.2 English
PP-OCRv5 mobile ONNX model. RapidOCR and PaddleOCR identify the relevant
components as Apache License 2.0 software. The pinned model source, version,
integrity hash, and model notice are distributed at
`windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook/ocr/MODEL-NOTICE-PPOCRV5.txt`;
the complete Apache License 2.0 text is beside it in
`LICENSE-PADDLEOCR.txt`.

Microsoft ONNX Runtime 1.29.0 executes the model locally under the MIT License.
Its complete license and redistributed third-party notices are beside the
model in `LICENSE-ONNXRUNTIME.txt` and
`THIRD-PARTY-NOTICES-ONNXRUNTIME.txt`. Screenshot pixels are not sent to these
projects or to any network service.

## BDO Codex and BDOLytics research references

BDO Codex and BDOLytics were credited research, cross-checking and mirror
references while Black Spirit Life assembled its own application-specific
planner and map records. The retained names, descriptions, recipes, prices,
IDs, coordinates, item icons and NPC portraits originate from Black Desert and
are classified as Pearl Abyss game content or factual information under the
fan-content basis above. Merely retrieving a PA asset through a browser page or
mirror does not make the website the owner of that asset.

The project owner confirms that Black Spirit Life does not retain either
site's page design, HTML, guides, commentary, annotations, custom translations
or other site-authored presentation. Their URLs and record IDs remain as
research provenance. No separate permission is required merely because an
ordinary PA game fact or asset appeared on either reference site.

A different source-boundary item is recorded precisely in `ASSET_SOURCES.md`
and `docs/public-release-source-matrix.md`: six tracked private research inputs
must not enter the public repository. Two contain complete single-source
world-map snapshots; four are narrower coordinate/vendor/portrait research
records excluded for repository hygiene. The runtime `workerNodes` dataset is
not one of those files. It contains PA facts selected, normalized, connected
and presented through Black Spirit Life's original map interface, rendering,
search, filtering, routing and calculations.

- Site: <https://bdocodex.com/>
- Contact page: <https://bdocodex.com/us/contacts/>
- BDOLytics: <https://bdolytics.com/>

## Workerman / Shrddr

Black Spirit Life uses or contacts Workerman / Shrddr material for the basemap,
node icons, lodging/house data, and upstream inputs to worker-income data.
Workerman is publicly hosted for community use and directs users to its public
GitHub issue tracker. No separate written licence covering these uses was
found; public hosting is not represented here as written permission.

- Source project: <https://github.com/shrddr/workermanjs>
- Public issue route: <https://github.com/shrddr/workermanjs/issues>
- Tile repository: <https://github.com/shrddr/shrddr.github.io/tree/main/maptiles>

The basemap hotlink/cache, 64 node icons, complete 812-house lodging graph and
Workerman-derived economics inputs have no recorded written licence. The
project owner has explicitly accepted the remaining practical risk for this
small credited noncommercial fan release and directed that the full
application remain intact. This is not represented as Workerman/Shrddr
permission. Black Spirit Life provides full attribution and will respond
promptly through its public issue route to any correction or removal request.
Each group remains independently replaceable for that purpose.
The absence of a separate licence file is not a publication blocker under the
project-owner decision. Reopen this position only if new concrete evidence
appears that Shrddr prohibits the use.

## SomethingLovely

The historical gathering-location layer includes 12,582 positions derived
from `fffam/blackdesert-somethinglovely-map` commit
`289c833d34851dc84f3a647a2d9cf604eda9c93a`. The upstream MIT notice is
bundled at
`packages/bdo_map_core/assets/licenses/SOMETHINGLOVELY-MIT.txt` and must remain
with every distribution containing that layer. The layer is explicitly
historical through 2021 and is not represented as complete current coverage.

- Repository: <https://github.com/fffam/blackdesert-somethinglovely-map>

The MIT notice covers the upstream project's licensed material; it does not
relicense Pearl Abyss intellectual property.

## bdo-empire

Worker-economics generation uses `bdo-empire` 0.8.1 at commit
`4a24b6f42926543e5f3eae5c8c559ebd689b698c`, whose original software is
offered under the Unlicense. The bundled inputs also trace to an unlicensed
Workerman game-data snapshot. Its retention is covered by the disclosed owner
risk decision above; the Unlicense for the calculation code does not become a
licence for those inputs.

- Repository: <https://github.com/Thell/bdo-empire>
- Bundled notice: `packages/bdo_map_core/assets/licenses/BDO-EMPIRE-UNLICENSE.txt`

## bdo-data-extractor

The private Edania cross-check seed was reduced from output produced by
`iDevelopThings/bdo-data-extractor` commit
`2e4ace61e2a3967663cb36580edb7201b7ca3fd4`. Its license covers its original
code and documentation only and does not grant rights in extracted Black
Desert data, assets, text, formats, or trademarks.

- Repository: <https://github.com/iDevelopThings/bdo-data-extractor>

The reduced seed contains Pearl Abyss-origin game facts under the fan-content
basis. It is a source-only research record, not a separately owned website
database or installer asset.

## Velopack

Velopack 1.2.0 is bundled for Windows packaging and updates under its upstream
license. The complete license is installed from
`windows/third_party/velopack/1.2.0/LICENSE`.

- Project: <https://velopack.io/>

## Other factual research sources

The planner contains citations or factual cross-checks to official Pearl
Abyss pages and to community references including BDO Codex, BDOLytics,
Caphras Archives, Black Desert Foundry, Garmoth, GrumpyG, Inven Global, and the
public market API at `api.blackdesertmarket.com`. These credits identify
research routes; they do not claim that the sites own the underlying Black
Desert facts. Black Spirit Life retains its own selection, normalization,
calculations, relationships, summaries and interface. Any actual copied site
expression or wholesale organized-data file is named separately and narrowly
in `docs/public-release-source-matrix.md`.

## Corrections and takedown requests

Use this repository's **Issues** tab and select **Content correction or
takedown**. Include the affected file, record, or screen; the source or rights
basis; and the correction or removal requested. Do not post private personal
information or confidential proof in a public issue. If sensitive evidence is
needed and no private contact route is listed, open a minimal issue asking the
project owner to provide one before sharing that evidence.
