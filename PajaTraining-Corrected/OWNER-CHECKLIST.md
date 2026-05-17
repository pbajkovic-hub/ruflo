# OWNER CHECKLIST — what only you can provide to get the app on your phone

Plain-language companion to `PajaTraining/BUILD-ON-MAC.md`. The "brain" of the
app — the part that decides exactly what you lift each day based on your
recovery — is **finished and corrected**. Everything left is the iOS app built
*around* it. Those are engineering steps. This page is only the handful of
things **a developer cannot do for you** — they need you.

## The one hard fact

The app is a native iPhone app. **It cannot be built on your Windows PC** —
Apple's tools (Xcode) only run on a Mac, and the health features only work on a
real iPhone. This is the single biggest gap, and it's a logistics gap, not a
coding one. You chose to run the Mac build yourself with a Claude Code session
on a Mac — `BUILD-ON-MAC.md` is the start-to-finish script for that session.

## Your checklist

1. **Get to a Mac with Xcode 15+.** Options, cheapest first: borrow a Mac;
   buy a used Mac mini; or rent a cloud Mac by the hour (e.g. MacStadium /
   "Mac in the cloud" services — ~hours, not a purchase). Any of these works;
   you only need it for the build sessions, not forever.

2. **Decide on the Apple signing tier.**
   - **Free** (a normal Apple ID): $0. The app installs on your phone but
     **must be re-signed every 7 days** (re-run the build). Fine for personal
     use if you don't mind that.
   - **Apple Developer Program: $99/year.** No 7-day expiry, and the
     background auto-refresh of Oura data + iCloud sync work reliably.
   - **Recommendation:** start free to see it on your phone; pay the $99 only
     once you want it to "just work" in the background.

3. **Generate your Oura Personal Access Token.** In Oura's developer settings
   (cloud.ouraring.com → Personal Access Tokens). You paste this into the app
   once during setup. It is stored securely on the phone (Keychain), never in
   our files. (Heads-up: rotate this if it ever appears in a chat or screen
   share — same as a password.)

4. **Confirm your real training numbers (P1).** The two programs (Push/Pull/
   Legs and Upper/Lower) are built in, but the app needs *your* actual working
   weights to prescribe loads. Either give the developer your current working
   weight + target reps for each main lift (Bench, Overhead Press, Deadlift,
   Pull-up, Squat, Romanian Deadlift, Barbell Row), or the app will ask you to
   enter each the first time it comes up. Nothing is invented for you.

5. **Body composition (P2) — already decided: via Apple Health.** Whatever
   writes to Apple Health (your scale / InBody app) gives weight, body-fat %,
   lean mass and BMI. The deeper InBody numbers (muscle mass, visceral fat,
   body water, BMR) aren't available from Apple Health and will be blank — a
   manual entry form for those is a later add, not needed for v1.

6. **Set expectations.** From a Mac with everything above, this is roughly
   **6–9 weeks of iOS work** before it's solidly on your phone (Xcode project,
   the on-device database, the screens, then testing on the device). The hard
   thinking — the adaptive engine — is already done and verified.

## Optional, parallel (does not block the phone build)

You still owe a real iPhone Health export when convenient (so the Apple-Health
fallback can be tested with your data), and the **Oura-style screen design
reference** for the web preview — drop it in `C:\Users\38160\Downloads\` or
paste it into a chat (email/Gmail can't reach a running session). Neither one
blocks the Mac build above; they just sharpen the preview and the test data.

---

**Bottom line:** the brain is done. Get a Mac + Xcode, decide free-vs-$99,
generate the Oura token, confirm your lifting numbers — then run
`BUILD-ON-MAC.md` and it goes on your phone.
