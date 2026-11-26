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

TrackMan has no public API. The app signs in the same way the TrackMan web
portal does:

1. Opens `login.trackmangolf.com/connect/authorize` (OAuth code flow + PKCE)
   in an in-app web view. You enter credentials on TrackMan's own page.
2. Intercepts the redirect to `portal.trackmangolf.com/account/callback`
   and reads the authorization code.
3. Exchanges it at `/connect/token` for an access token (7 days) and a
   refresh token, stored in the Keychain.
4. Refreshes silently before each sync; you only sign in again if the
   refresh token is revoked.

This borrows the portal's public OAuth client id, which is undocumented and
may change. All of those values live in
`Packages/TrackManKit/Sources/TrackManKit/TrackManConfig.swift`.

## Layout

| Path | What |
| --- | --- |
| `Packages/TrackManKit` | OAuth/PKCE, Keychain, GraphQL client and queries, metrics. Unit tested. |
| `GolfDash/Auth` | Session state and the TrackMan login sheet |
| `GolfDash/Store` | SwiftData models and sync |
| `GolfDash/Views` | Dashboard, detail screens, settings |

Never commit a TrackMan token; `.gitignore` excludes the POC's `token` file.
