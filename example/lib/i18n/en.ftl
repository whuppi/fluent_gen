# Base-locale fixture. Every shape the generator supports appears at
# least once: plain message, NUMBER, DATETIME, plural selector, string
# selector, attributes, inline markup, transitive message references,
# and a comment type pin.

hello = Hi

# A comment type pin: usage alone leaves $name as Object?, and the
# `(String)` annotation narrows it.
# $name (String) - the person to greet.
welcome = Hello, { $name }!

items = You have { $count ->
    [one] one new message
   *[other] { $count } new messages
}.

# A string selector — its default is *[other], but the non-plural
# keys make it a String, not a num.
device = Open the { $platform ->
    [ios] App Store
    [android] Play Store
   *[other] store
}.

price = Total: { NUMBER($amount, style: "currency", currency: "USD") }
launchedAt = Launched at { DATETIME($d, dateStyle: "medium") }

# Inline markup — generates an AsSpans sibling.
banner = Read <bold>{ $title }</bold> on our blog.

# A transitive message reference: greeting supplies $name, so the
# generated welcomeBack takes both $name and $when.
greeting = Hi again, { $name }
welcomeBack = { greeting } — last seen { DATETIME($when, dateStyle: "short") }

# Attributes — emit per-attribute methods, each demanding only its
# own pattern's variables.
login = Sign in
    .title = Welcome back
    .helper = Tap to continue, { $name }
