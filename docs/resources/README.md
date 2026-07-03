# Snorry brand & design resources

## In-repo

| Resource | Purpose |
|----------|---------|
| [BRAND_GUIDE_APP.md](../../BRAND_GUIDE_APP.md) | iOS app UI, copy, tokens, screen specs (source) |
| [BRAND_GUIDE_APP.pdf](BRAND_GUIDE_APP.pdf) | PDF export of the app brand guide (regenerate from markdown when the spec changes) |
| [FEATURES.md](../../FEATURES.md) | Product features and use cases |
| [SUBSCRIPTION_SETUP.md](../../SUBSCRIPTION_SETUP.md) | App Store subscription configuration |

## Marketing brand guide (PDF)

**Snorry Brand Guide v3.0** — Instagram, ads, App Store creative, photography, motion for social.

- Optional copy in this folder: `brand-guide-v3.pdf`
- External copy may live at `~/Downloads/snorry-brand-guide-v12.pdf` (filename v12, cover v3.0)

When updating marketing materials, use the marketing PDF. When updating the app, edit **BRAND_GUIDE_APP.md** and keep marketing copy in sync.

**Regenerate app guide PDF** (after editing the markdown):

```bash
pandoc BRAND_GUIDE_APP.md -o docs/resources/BRAND_GUIDE_APP.pdf --pdf-engine=typst
```

Requires [Pandoc](https://pandoc.org/) and [Typst](https://typst.app/) (`brew install pandoc typst`).

## App icons

- `Snorry/Assets.xcassets/AppIcon.appiconset/` — App Store / home screen
- `Snorry/Assets.xcassets/HomeAppIcon.imageset/` — in-app toolbar wordmark icon
