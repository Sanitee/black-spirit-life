# Truffle Mushroom location and photo provenance

Review date: 2026-08-28

## What ships in the Beta

- 96 exact Truffle Mushroom dots from the MIT-licensed SomethingLovely
  historical dataset, explicitly labeled stale and historical through 2021.
- 13 radius-free named-area navigation focuses from Pearl Abyss's official
  November 2, 2022 update. That update lists 87 mushrooms across Serendia,
  Calpheon, Mediah, and Drieghan and states that respawn time was reduced by
  33%.
- Four English official regional overview images displayed from Pearl Abyss's
  CDN. Each named-area focus opens only its matching region image. Individual
  historical dots intentionally receive none of these regional images.

Official source:
https://www.console.playblackdesert.com/News/Notice/Detail?boardNo=12103&boardType=2&countryType=en-US

The official overview images are regional guides. They are not represented as
photos of the exact selected mushroom, a cave entrance, or current spawn
proof. Named-area markers reuse reviewed node centers; the second Hasrah focus
uses an existing MIT historical truffle coordinate so the generator never
invents offset geometry.

## Community screenshot boundary

Current community guides, forum posts, Reddit discussions, and videos were
reviewed for the claim that locations exist outside BDO Codex. They provide
useful route advice and actual cave screenshots, but no specific additional
coordinate was found with enough independently reproducible evidence to add an
exact pin. GrumpyG's cave guides provide the strongest collection of individual
node and cave-entrance photos, but its published terms reserve article and
original-image rights. The reviewed YouTube guides use the standard YouTube
license rather than a reusable Creative Commons license. BDO Codex comment
images and other forum screenshots likewise do not carry a clear license that
permits rebundling in the application.

Therefore the Beta does not copy community screenshots, transcribe
third-party map dots, trace video frames, or create “secret” ghost pins. A
future exact location or entrance photo may be added after either:

1. a direct in-game survey recorded under the gathering survey protocol; or
2. written reuse permission from the original screenshot author, with author,
   source URL, license, caption, and verification date retained.

Useful reviewed references that remain links only:

- https://grumpygreen.cricket/truffle-mushroom/
- https://grumpygreen.cricket/secret-cave-centralguardcamp-truffle-mushrooms/
- https://grumpygreen.cricket/secret-cave-moretti-plantation-truffle-mushrooms/
- https://grumpygreen.cricket/secret-cave-alejandro-farm-truffle-mushrooms/
- https://www.reddit.com/r/blackdesertonline/comments/x6dwte/current_status_of_elixirs_of_detection_and/
- https://www.reddit.com/r/blackdesertonline/comments/s09j49/since_we_are_in_beta_once_again/
- https://www.tw.playblackdesert.com/zh-tw/Forum/ForumTopic/Detail?_opinionNo=0&_topicNo=40123
- https://www.youtube.com/watch?v=opuLQV6K8Tg

## UI behavior

The location-photo lightbox fills the available app window, is keyboard
accessible, supports previous/next navigation, closes with Escape, and uses
an `InteractiveViewer` with up to 4x zoom. It always shows the caption, source
title, attribution, license, source URL, and review date. An exact historical
dot with no cleared, individually matched photograph shows an explicit status
instead of inheriting a regional map.
