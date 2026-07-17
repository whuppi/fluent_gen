# Non-base locale — partial coverage by design. The validator
# will warn about the gaps; the build should still succeed.

hello = Salut
welcome = Bonjour, { $name } !
items = Vous avez { $count ->
    [one] un nouveau message
   *[other] { $count } nouveaux messages
}.
# `price`, `launchedAt`, `banner`, and `login.*` deliberately
# omitted — surfaces missing-message warnings.

# `bonjour` deliberately invented — surfaces an orphan-message
# warning.
bonjour = Bonjour le monde
