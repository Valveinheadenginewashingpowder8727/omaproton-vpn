# Contributing

Thanks for using OmaProton VPN. Feedback is very welcome — **code is not.**

## This repository has one author, on purpose

This widget handles a VPN. It runs unsandboxed inside your Omarchy shell and
it opens the terminal you type your Proton password into. For that reason
every line in it is written and reviewed by one person, and only that person
can commit:

- There are no collaborators and there never will be.
- **Pull requests are not accepted and will be closed unread**, whatever they
  contain. This isn't a judgement on your code — it's so that nobody, ever,
  has to wonder whether a stranger's change made it into a VPN widget.
- GitHub Actions are disabled on this repository, so nothing runs on a PR.

## What is welcome

**Open an issue** for anything:

- **Bugs** — what you did, what you expected, what happened. The output of
  `omarchy-shell io.github.grichard99.omaproton-vpn debug` (it contains no
  account details) and your Omarchy version help a lot.
- **Feature requests** — what you're trying to do, not just the feature. Good
  ideas get built; several already came from users.
- **Design / UX feedback** — screenshots welcome. If something felt confusing,
  that's a bug.
- **Docs** — if the README didn't answer your question, say what you looked
  for.

If you've found a **security problem**, please don't open a public issue —
see [SECURITY.md](SECURITY.md).

## What happens to your issue

It gets read, labelled, and answered. If it's going to be built, it's assigned
to a release milestone and you'll be pinged when it ships. If it isn't, you'll
be told why.
