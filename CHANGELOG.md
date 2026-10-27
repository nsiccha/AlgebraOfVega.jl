# Changelog

All notable changes to AlgebraOfVega.jl are documented here, newest first.
Changes before 0.2.1 are recorded in the git history only.

Every landing that adds or changes public API (an export, a keyword, a method,
or documented behaviour a dependant can rely on) bumps the patch digit in
`Project.toml` and adds its entry under a new heading at the top of this file.
An entry that breaks something a dependant relies on says **Breaking:** and
what to change. The minor digit is the breaking one in
[semantic versioning](https://semver.org/) before 1.0.
A package or app that calls that API states the version as its floor, for
example `[compat] AlgebraOfVega = "0.2.1"`. An environment that pins an older
AlgebraOfVega commit is then refused when it resolves, with
`Unsatisfiable requirements detected for package AlgebraOfVega`, instead of
failing at run time with a `MethodError`.

## 0.2.2

- A spec's HTML fragment (`to_html(spec)`, which is also the spec's
  `text/html` `show` and so what HTMXObjects' `SemanticPlot` writes) draws
  when it is inserted into a page that has already loaded, such as an htmx
  swap into a page without `vega_head()`. The browser runs a swapped inline
  script before the Vega `<script src>` tags above it have downloaded, so the
  first such figure used to stay empty with only a
  `ReferenceError: vegaEmbed is not defined` in the console. The embed now
  waits for its own Vega scripts. If one of them fails to load, the plot's
  container and the console say which, and name `vega_head()`.

## 0.2.1

- Two configs compose into one. For two `config(...)` terms `a` and `b`,
  `a * b` is the config that `spec * a * b` applies (object-valued properties
  deep-merged, the right one winning a conflicting key), so
  `spec * (a * b) == spec * a * b`. An app extends a shared config with its
  own settings once, `const GERMAN = SHARED * config(config = …)`, and uses
  `spec * GERMAN` wherever it used `spec * SHARED`. Before, `Config * Config`
  threw a `MethodError`.
