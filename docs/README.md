# Documentation maintenance

The repository README is the project front page. Detailed usage lives in the
[GitHub wiki](https://github.com/NilaBlueshirt/WfTune/wiki), with its Markdown
sources versioned in [`wiki/`](wiki/) so documentation changes can be reviewed
alongside code.

## Page map

| Source | Contents |
| :--- | :--- |
| [Home](wiki/Home.md) | Documentation entry point and guide navigation. |
| [Getting started](wiki/Getting-Started.md) | Requirements, installation, synthetic quick start, and unit tests. |
| [Execution paths](wiki/Execution-Paths.md) | Workflow managers and backend support. |
| [Measurement protocol](wiki/Measurement-Protocol.md) | Metrics, collection roles, and the trust boundary. |
| [Campaign guide](wiki/Campaign-Guide.md) | Preparation, preflight, collection, version recording, data separation, and operational safety. |
| [Analysis](wiki/Analysis.md) | Auditing, summaries, plots, cross-WMS comparisons, and version checks. |
| [Manual Nextflow runner](wiki/Manual-Nextflow-Runner.md) | Manual collection lifecycle and troubleshooting. |
| [Energy tools](wiki/Energy-Tools.md) | RAPL/PDU sampling and calibration. |
| [Repository layout](wiki/Repository-Layout.md) | Source directories and naming conventions. |
| [Citation](wiki/Citation.md) | Paper links, copyable BibTeX and plain-text references, and research provenance. |

`_Sidebar.md` and `_Footer.md` provide shared wiki navigation. Links between
published pages use full wiki URLs; links to source files and images point to
the main repository because the wiki has its own Git repository.

## Publishing

Edit the sources in `docs/wiki/` and review them with the corresponding code
changes. GitHub stores wiki pages separately, so committing these sources to
the main repository does **not** publish them automatically.

For a new wiki, save an initial `Home` page using GitHub's
[Create the first page](https://github.com/NilaBlueshirt/WfTune/wiki) button.
GitHub requires this initialization before the wiki can be cloned; see
[GitHub's wiki documentation](https://docs.github.com/en/communities/documenting-your-project-with-wikis/adding-or-editing-wiki-pages#adding-or-editing-wiki-pages-locally).

Then, from the WfTune repository root, publish with Git credentials that have
write access to the repository:

```bash
WFTUNE_WIKI_CHECKOUT=$(mktemp -d /tmp/wftune-wiki.XXXXXX)
git clone https://github.com/NilaBlueshirt/WfTune.wiki.git "$WFTUNE_WIKI_CHECKOUT"
```

If cloning succeeds, copy the reviewed pages and inspect the staged changes:

```bash
cp docs/wiki/*.md "$WFTUNE_WIKI_CHECKOUT/"
git -C "$WFTUNE_WIKI_CHECKOUT" add -- '*.md'
git -C "$WFTUNE_WIKI_CHECKOUT" diff --cached --stat
git -C "$WFTUNE_WIKI_CHECKOUT" diff --cached
```

If the diff contains the intended updates, commit and publish:

```bash
git -C "$WFTUNE_WIKI_CHECKOUT" commit -m "Update WfTune documentation"
git -C "$WFTUNE_WIKI_CHECKOUT" push origin HEAD
```

An empty diff means the pages are already synchronized. The copy step updates
these pages and leaves other wiki pages intact. For intentional page removals
or renames, update the wiki checkout explicitly and repair incoming links.
If someone edits the wiki directly on GitHub, reconcile those changes with
`docs/wiki/` before publishing again.
