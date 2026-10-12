# Release checklist — حاسبة الهاند

## 1. Two-phone Bluetooth test

The simulator has no Bluetooth, so everything below has only been compiled and unit-tested, never run. You need two iPhones on iOS 18 or later, both with this build installed from Xcode.

**Host** is the scorekeeping phone. **Guest** is the other player's phone. Turn Bluetooth on for both.

### Join
1. Host: Settings (gear) → turn on **مشاركة اللعبة عبر البلوتوث** → allow Bluetooth → close Settings.
   - [ ] An **بانتظار اللاعبين القريبين** card appears at the top of the start page.
2. Guest: tap the antenna in the dock (**تابع لعبة على جوال قريب**).
   - [ ] The guest is asked **ما اسمك؟** this once. Enter a name and tap **متابعة**, then allow Bluetooth.
   - [ ] With only one table nearby, the guest joins on its own within about two seconds.
   - [ ] The guest's waiting screen shows its name and **بانتظار المضيف ليختار مقعدك**.
   - [ ] A Live Activity saying **بانتظار بدء اللعبة** appears on the guest's lock screen.
   - [ ] On the host, the guest pops into the nearby row with the bubble-up animation.

### Seat
3. Host: tap a seat on the table.
   - [ ] In the editor, the guest appears first, as a black chip, ahead of the saved names.
4. Tap the guest's chip.
   - [ ] The seat pops and shows the guest's name with a green link badge.
   - [ ] The guest disappears from the nearby row and from the other seats' editors.
   - [ ] Within a second the guest's screen shows **مقعدك: …** with its seat raised in black.
5. Host: reopen that seat and type a different name.
   - [ ] The guest is released: it reappears in the nearby row, and its own screen goes back to waiting.
   - [ ] Seat it again.
6. Optional, if you have a third phone: give it the same name as the guest.
   - [ ] It appears with a ` 2` suffix.

### Start
7. Host: fill the other seats by typing, then press ▶.
   - [ ] The guest's screen switches to the live game on its own, with **نتيجتك** showing its seat.
   - [ ] The guest's Live Activity switches from waiting to the game.

### Record a round
8. Host: tap the winner's bubble → choose a win type.
   - [ ] On the host, the score deltas float up and the chart extends.
   - [ ] The guest's total, rank and table update within a second or two.
9. Repeat until round 7.
   - [ ] On the guest, the advice card and Live Activity show **لتتصدر تحتاج** with the needed win types.

### Lock the guest's phone
10. Lock the guest's phone and record two more rounds on the host.
    - [ ] The guest's lock-screen Live Activity updates each round without unlocking: scores, its seat in black, the advice line.
    - [ ] A lock-screen widget, if one has been added, also updates.

### Disconnect and reconnect
11. Walk the guest out of range, or turn the guest's Bluetooth off, for about 30 seconds.
    - [ ] The host's link badge on that seat disappears, and the name stays.
    - [ ] The guest shows **نعيد الاتصال…** and the Live Activity shows **غير متصل**.
12. Come back in range, or turn Bluetooth on again.
    - [ ] The guest reconnects without anyone tapping anything.
    - [ ] The host's link badge returns, and the next round reaches the guest.
13. Force-quit the guest app, then record a round on the host.
    - [ ] iOS relaunches the guest in the background and its lock screen still updates. If it doesn't, note it: this relies on Bluetooth state restoration.

### Also worth checking
- [ ] Host taps **‹** to pause. The guest returns to the waiting screen with its seat kept. After **resume**, the guest returns to the game.
- [ ] Rematch (↺) and **لاعبون جدد**: the guest keeps its seat.
- [ ] A guest who joins after the game has started can tap its own seat on the table.
- [ ] With Bluetooth off on the host, the nearby row is hidden and typing names still works.

## 2. Before you archive

- [ ] **Signing & Capabilities**, for both the app and the widget extension:
  - Team **YT255QF3C2**.
  - App Group `group.KHALID.Rummy-Calculator` registered in the developer portal.
- [ ] App target, **Background Modes**:
  - [ ] **Uses Bluetooth LE accessories** is ticked.
  - [ ] **Acts as a Bluetooth LE accessory** is ticked.
  - Both keys are already in `Rummy-Calculator-Info.plist`; Xcode shows them as ticked.
- [ ] Bump `CURRENT_PROJECT_VERSION` (build number) for every upload. `MARKETING_VERSION` is 1.0.
- [ ] Run once on the smallest phone you support (for example an iPhone SE) and check the start page and game screen fit.
- [ ] Optional: `CarpetBackground` (216 KB) is no longer used by any screen. Delete it to trim the app size.
- [ ] Product → Archive → Distribute App → App Store Connect.

## 3. App Store Connect

- **Privacy nutrition label: "Data Not Collected".**
  - Nothing leaves the phone except the Bluetooth link to phones at the same table.
  - There's no server, no account and no analytics.
- **Privacy policy URL** is required even when no data is collected. Host a short page saying that:
  - scores, names and history stay on the device;
  - Bluetooth is used only to share the live game with nearby players' phones;
  - nothing is collected or sent to any server.
- **Export compliance:** already answered in the build (`ITSAppUsesNonExemptEncryption = NO`).
- **Age rating:** a scorekeeper for a card game, with no real-money or simulated gambling. Answer "None" throughout.
- **Category:** Utilities, or Games → Card if you prefer.
- **Primary language:** Arabic.
- **Screenshots:** iPhone 6.9" (1320 × 2868) is required. Good candidates:
  - the start page;
  - the game screen mid-game, with the chart;
  - the winner picker;
  - the celebration;
  - the standings (الترتيب العام), on the leaderboard or a head-to-head;
  - a lock-screen Live Activity.

### Notes for App Review

Paste into **App Review Information → Notes**:

> The app keeps score for the card game Hand (هاند). It works fully offline.
>
> Optional feature: players at the same table can follow the game on their own phones. The scorekeeper turns on "مشاركة اللعبة عبر البلوتوث" in Settings. The other phones tap the antenna button on the start page. Scores then reach their Live Activity on the lock screen over Bluetooth LE.
>
> The bluetooth-central and bluetooth-peripheral background modes are used only for this. The scorekeeper's phone keeps sharing while it is locked between rounds, and players' phones receive each round's scores while locked. No data leaves the devices. Testing this needs two iPhones; the rest of the app works on one.
