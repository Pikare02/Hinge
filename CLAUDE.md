# Hinge

## Docs language

This repository writes markdown in English, overriding the usual Japanese
default. `README.ja.md` is the one exception: it is the Japanese translation of
`README.md`, so keep the two in step whenever either changes.

## After changing the transform

Run `.build/debug/Hinge --selfcheck`. It asserts the invariants the illusion
rests on, and it is cheaper than launching the overlay to look.
