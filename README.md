# Golf Dash

A personal iPhone app that signs in to TrackMan and shows dashboards of your
golf data. Phase one has two cards:

- **Average drive**: each course round's drive average, with a 5-round rolling average.
- **Swings per day**: full swings (putting excluded) for the last 30 days.

Data is cached on the phone (SwiftData) and refreshed incrementally. There is
no backend.

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
3. The web view keeps the portal session cookie. When the token expires, the
   app calls `/api/account/me` again with that cookie for a fresh one, so you
   only sign in again when the portal session ends.

This relies on undocumented portal behaviour that TrackMan could change. The
URLs live in `Packages/TrackManKit/Sources/TrackManKit/TrackManConfig.swift`.

## Layout

| Path | What |
| --- | --- |
| `Packages/TrackManKit` | Portal session and token renewal, Keychain, GraphQL client and queries, metrics. Unit tested. |
| `GolfDash/Auth` | Session state and the TrackMan login sheet |
| `GolfDash/Store` | SwiftData models and sync |
| `GolfDash/Views` | Dashboard, detail screens, settings |

Never commit a TrackMan token; `.gitignore` excludes the POC's `token` file.
