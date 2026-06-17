# spec-kit-extensions

Community extensions for [Spec Kit](https://github.com/github/spec-kit). Each
extension lives in its own subdirectory with its own `extension.yml`, README, and
changelog.

## Extensions

| Extension | What it does |
|-----------|--------------|
| [`blueprint`](./blueprint) | A living, collapsing architecture map for spec-driven projects + a deterministic CI gate that flags when specs, the map, and the code drift apart (greenfield or brownfield). |

## Installing an extension

```bash
# from a tagged release
specify extension add blueprint \
  --from https://github.com/ogil109/spec-kit-extensions/releases/download/blueprint-v1.0.0/blueprint.zip

# or, for local development against a checkout
specify extension add --dev /path/to/spec-kit-extensions/blueprint
```

## Releasing (maintainers)

Per-extension release assets are plain zips of the extension directory, so
`specify extension add --from <zip>` finds the manifest:

```bash
# from the repo root
zip -r blueprint.zip blueprint -x '*/.git/*'
# create a release tagged blueprint-vX.Y.Z and upload blueprint.zip as an asset
gh release create blueprint-v1.0.0 blueprint.zip \
  --title "blueprint v1.0.0" --notes-file blueprint/CHANGELOG.md
```

Then file an **Extension Submission** issue on `github/spec-kit` so a maintainer
can add the catalog entry. (Community extensions are listed via the issue
template, not by PR.)

## License

[MIT](./LICENSE)
