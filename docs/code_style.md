# Code style

Conventions for code, templates and tests in this repository, for humans and AI agents alike. They come on top of `mix format` (120 columns), `mix credo --strict`, and the rules Phoenix writes for agents in `deps/phoenix/usage-rules/`: `elixir.md`, `ecto.md` and `phoenix.md` for all code, `html.md` and `liveview.md` for templates and LiveViews. Where those rules and this file disagree, this file wins. `deps/` is ignored by git, so search tools skip it: open these files by path.

## Code

- **Few comments.** Code should read on its own. Comment the *why* that can't be inferred (a workaround, a production incident, a library quirk), not what the next line does. Same for `@doc` and `@moduledoc`: state intent, gotchas and non-obvious return shapes; don't restate the signature.
- **Use helper function names to avoid comments.** Move blocks of code into helper functions whose names say what they do, so the code documents itself.
- **Pipe (`|>`) a lot.** With the previous recommendation, a good main function can just pipe its first argument through a series of helper functions.
- **No unused parameters.** When a change makes an argument useless, remove it from the function and from every caller, including functions that only pass it along. Don't keep it as `_param`.
- **Queries live on the schema module.** The project doesn't use Phoenix contexts. Ecto query functions go on the `DB.*` schema they query (e.g. `DB.IRVEValidFile.orphan_files/1`), after the `typed_schema` block, and are tested in `apps/transport/test/db/<schema>_test.exs`. A module with a specific role (e.g. `Transport.IRVE.DatabaseExporter`) keeps to that role.
- **HTTP goes through Req** ([ADR 001](adr/001-http-client.md)), called through `Transport.Req.impl()` so tests can mock it. No new HTTPoison code; Finch only with a comment saying why Req can't do it.
- **`Task.async_stream` gets an explicit `timeout:`** sized to the work, and the code decides what a timeout does: `on_timeout: :kill_task` and handle `{:exit, :timeout}`, or let it crash on purpose. Neither the 5 s default nor the `timeout: :infinity` that Phoenix's `elixir.md` suggests. Most of these calls run in background jobs that nobody watches or stops: a task stuck forever, e.g. on a download that keeps trickling bytes, holds the job and a slot of its queue, and nothing reports it. A bounded timeout turns it into a failure that shows up in Sentry or as an Oban retry.
- **Verified routes** (`~p"/datasets/#{dataset.slug}"`) for every path. No new `Routes.*` helper calls; the few left in tests are to go.
- **Reversible migrations**: they run at every deployment. Generate them from the app: `cd apps/transport && mix ecto.gen.migration <name>`.
- **Scripts** go under `scripts/<domain>/`, in Elixir (or bash), with their usage in a header comment. Downloads go to `cache-dir/`, which git ignores.
- **Small, in-place diffs when refactoring.** Keep the order of functions and tests, rename only what has to change, and leave the surrounding blocks as they are, so the diff shows what changed rather than a rewrite.

## Templates and assets

New and rewritten templates follow what `mix phx.new` 1.8 generates. References: the LiveView guide [Assigns and HEEx templates](https://phoenix-live-view.hexdocs.pm/assigns-eex.html), and Phoenix's `html.md` and `liveview.md` (their one Tailwind example doesn't apply: the site uses template.data.gouv.fr classes and its own SCSS). Much of the existing code predates these rules: apply them to the blocks you write or rewrite, without converting whole files along the way.

- **`{…}` interpolation**, in attributes and tag bodies alike. No `<%= expr %>`.
- **`:if` and `:for` on the tag** (`<li :for={dataset <- @datasets}>`) rather than `<%= if %>` / `<%= for %>` blocks. Keep a block for `case` and `cond`, or when there is no tag to carry the attribute. `:for` takes a single generator: flatten nested loops in a helper.
- **No variables in templates** (`<% x = … %>`), and no `assigns.x` or `assigns[:x]`: they break LiveView change tracking. Compute the value in the controller or LiveView (`assign/3`, defaults in `mount`), in a view helper, or with `assign/3` at the top of a function component; never `Map.put/3` on `assigns`.
- **Function components** for reusable markup, with `attr` and `slot` declarations, rather than new `render("_partial.html", …)` partials. Pass explicit attributes (`<.card title={@title} />`), not the whole `{assigns}`.
- **New views use `use TransportWeb, :html`** and `embed_templates`, named `TransportWeb.<Name>View` (controllers look up `<Name>View`, see `formats:` in `transport_web.ex`). A template added to an existing view stays in that `Phoenix.View` module. This overrides the "don't use `Phoenix.View`" rule in `deps/phoenix/usage-rules/phoenix.md` until the app has moved off `Phoenix.View`.
- **Forms, buttons and links come from `TransportWeb.CoreComponents`**: `<.form for={@form}>` built with `to_form/2`, `<.input field={@form[:name]} label="…">`, `<.button>`, and `<.link href={~p"/datasets"}>` (`navigate` or `patch` in LiveViews). No `form_for` or other `phoenix_html_helpers` functions: that dependency is a bridge, to be removed.
- **Class lists**: `class={["sort-icon fa", sort_icon(@field, @order_by)]}`.
- **HEEx comments**: `<%!-- … --%>`. An HTML comment `<!-- … -->` is sent to the browser.
- **Links inside translated sentences**: the msgstr carries the whole sentence with its `<a href=\"%{url}\">`, and the template passes only the URL: `{raw(dgettext("explore", "bnlc-explanation", url: ~p"/datasets/#{@bnlc_dataset.slug}"))}`. Never split a sentence around a link: word order differs between languages.
- **Assets**: JavaScript and SCSS live in `apps/transport/client` and are built by Webpack, not esbuild.

## Tests

- **Full module names, no `alias` for the code under test**: `Transport.IRVE.Validator.validate_and_summarize(body)`, not `alias Transport.IRVE.Validator` then `Validator.validate_and_summarize(body)`. Each call says exactly what is exercised. Run `mix format` afterwards: full names often push lines past 120 columns.
- **Terse titles**: say what is asserted, then stop (`"mark_unlisted/2 keeps the first date"`).
- **Flat tests** when the file exercises one function, or nearly; `describe "function/arity"` blocks when it covers several.
- **Few comments**, as in code.
- **Mocks**: Mox, with `setup :verify_on_exit!`. HTTP is mocked with `Transport.Req.Mock`; the other boundaries (S3, validators, …) have their own mocks, listed in `config/test.exs`. Tests never reach the network.
- **Data**: ExMachina factories from `DB.Factory` (`apps/transport/test/support/factory.ex`), e.g. `insert(:irve_valid_file, datagouv_resource_id: "…")`. Database tests check out the Ecto sandbox in `setup` (`Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)`).
