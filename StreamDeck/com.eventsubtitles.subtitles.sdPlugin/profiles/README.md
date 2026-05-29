# Pre-defined Profile

The installed Elgato schema supports manifest `Profiles` entries that point to real `.streamDeckProfile` files. This package does not include one because the local CLI does not provide a documented profile generator and no GUI-exported profile is available in this worktree.

The manifest intentionally omits `Profiles` so packaging remains valid. Add a real Stream Deck-exported `.streamDeckProfile` here before declaring profile support in `manifest.json`.
