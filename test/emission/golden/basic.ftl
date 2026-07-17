hello = Hi
welcome = Hello, { $name }!
items = You have { $count ->
    [one] one new message
   *[other] { $count } new messages
}.
price = Total: { NUMBER($amount) }
launchedAt = Launched at { DATETIME($d) }
