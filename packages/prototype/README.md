# ListRunner interactive prototype

A small, standalone browser prototype of the ListRunner iPhone shopping flow. It runs separately from the existing mobile app and does not make real Coles requests or store cart changes.

```bash
cd packages/prototype
npm start
```

Open http://localhost:4178. On a desktop it appears in an iPhone-sized frame; on a phone it fills the screen.

Try pasting or adding groceries, opening the simulated store, editing the store search, selecting neighboring cards, marking an item added, undoing during the three-second confirmation, skipping items, collapsing/expanding the overlay, dismissing the store with the native sheet handle, and finishing the run. The sample list can be restored at any time.

This prototype focuses on the list-to-store flow. Native integrations (real Coles browsing/cart observation, Apple Reminders, persistence, VoiceOver/Switch Control integration, and system settings) are represented only where needed to demonstrate the interaction and are not implemented here.
