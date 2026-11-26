# Training Strokes

A personal iPhone app that signs in to TrackMan and shows dashboards of your
golf data, in two tabs along the bottom:

- **Home**: swings this month and all time, practice streak, TrackMan
  handicap, a month calendar of TrackMan days, the latest round, and swings
  per day.
- **Driver**: drive distance per round with a 5-round average, longest
  drive, fairways hit and missed left or right, and practice driver numbers
  (carry, ball and club speed, smash, launch, spin, dispersion) for 30 days,
  90 days or all time.

Data is cached on the phone (SwiftData) and refreshed incrementally. Practice
shots are downloaded once per session, so the first sync after installing
takes longer. There is
no backend.

The project, target and bundle id keep the working name `GolfDash`, so an
installed copy updates in place and stays signed in. The home-screen name,
icon and theme are Training Strokes: the icon source is
`design/app-icon.svg`, the colors are in `GolfDash/Assets.xcassets` (light
and dark), and `GolfDash/Theme.swift` holds the fonts and the welcome-screen
mark. The landing page is `site/index.html`.

## Run it

Requirements: a Mac with Xcode 15.3 or later, and an iPhone on iOS 17+.

```sh
brew install xcodegen        # once
xcodegen generate            # creates GolfDash.xcodeproj from project.yml
open GolfDash.xcodeproj
```

In Xcode, select the **GolfDash** target, open **Signing & Capabilities**,
and pick your Personal Team. If Xcode says the bundle id is taken, change
`PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` and regenerate. With free signing
the app must be reinstalled from Xcode every 7 days.

Run the logic tests without a simulator:

```sh
cd Packages/TrackManKit && swift test
```

## How sign-in works

TrackMan has no public API, and its web portal signs in on its own server
(it holds the OAuth client secret), so the app cannot redeem a login code
itself. Instead it signs in through the portal, like a browser:

1. The login sheet loads `portal.trackmangolf.com` in a web view, which sends
   you to TrackMan's own login page. You type your credentials there.
2. Once the web view is back on the portal, the app reads the portal's
   `/api/account/me`, which returns the bearer token the portal itself uses
   (valid 7 days). The token is stored in the Keychain.
3. The app saves TrackMan's cookies (portal and login) in the Keychain and
   puts them back into the web view at launch, because session cookies do
   not survive iOS closing the app. When the token expires, the app calls
   `/api/account/me` again with those cookies for a fresh one, and keeps any
   cookie the portal renews.
4. If TrackMan ends the session anyway, the app reopens the login sheet. The
   saved login cookie usually signs you straight back in; if not, the
   TrackMan page accepts iPhone password AutoFill (the key above the
   keyboard). The app never sees or stores your password.

Only **Sign out** in Settings clears the token and the saved cookies.

This relies on undocumented portal behaviour that TrackMan could change. The
URLs live in `Packages/TrackManKit/Sources/TrackManKit/TrackManConfig.swift`.

## Layout

| Path | What |
| --- | --- |
| `Packages/TrackManKit` | Portal session and token renewal, Keychain, GraphQL client and queries, metrics. Unit tested. |
| `GolfDash/Auth` | Session state and the TrackMan login sheet |
| `GolfDash/Store` | SwiftData models and sync |
| `GolfDash/Views` | Tab bar, Home, Driver, detail screens, settings |
| `tools/find_handicap_field.py` | Lists TrackMan schema fields that look like a handicap |

Never commit a TrackMan token; `.gitignore` excludes the POC's `token` file.
