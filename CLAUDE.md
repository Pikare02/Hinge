# Hinge

## Docs language

`README.md` is written in English, overriding the usual Japanese default for
markdown. `README.ja.md` is the Japanese translation of it; keep the two in
step when either changes. `docs/spec.md` stays in Japanese.

## After changing the transform

Run `.build/debug/Hinge --selfcheck`. It asserts the invariants the illusion
rests on, and it is cheaper than launching the overlay to look.
