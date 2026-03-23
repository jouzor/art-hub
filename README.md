# Digital Art Commission Hub

**Smart Contract Reference** · Language: Clarity 2+ · Network: Stacks · File: `artHub.clar`

---

## Overview

The Digital Art Commission Hub is a Clarity smart contract deployed on the Stacks blockchain that manages a decentralised marketplace for digital art commissions. It allows artists to register profiles, create commission projects, submit artwork deliverables, and claim payments — all governed by on-chain rules enforced without intermediaries.

---

## Architecture

### Data Variables

| Variable | Type | Description |
|---|---|---|
| `gallery-curator` | principal | Administrator address; controls fund allocation and curator delegation |
| `art-fund` | uint | Total balance available for paying out completed commissions |
| `artist-community` | uint | Running count of all registered artists |

### Data Maps

| Map | Key | Description |
|---|---|---|
| `digital-artists` | principal | Artist profile: score, submissions, rank, earnings, open projects |
| `art-projects` | {artist, project-ref} | Per-project record: requirements, progress, deadline, payment |
| `artist-accolades` | principal | List of up to 10 achievement strings earned by the artist |

---

## Error Codes

| Constant | Code | Meaning |
|---|---|---|
| `ERR-PERMISSION-DENIED` | u100 | Caller is not the gallery curator |
| `ERR-ARTIST-REGISTERED` | u101 | Artist already exists in the registry |
| `ERR-ARTIST-UNKNOWN` | u102 | Artist has not registered yet |
| `ERR-SPECIFICATION-FAILED` | u103 | Invalid input or state for the operation |
| `ERR-GALLERY-EMPTY` | u104 | Insufficient funds in the art fund |
| `ERR-PAYMENT-FAILED` | u105 | Invalid payment amount (must be > 0) |
| `ERR-SUBMISSION-FAILED` | u106 | Piece quantity must be greater than zero |
| `ERR-PROJECT-FAILED` | u107 | Project reference is out of range or not found |

---

## Public Functions

### `register-digital-artist`

Registers the transaction sender as a new artist. Initialises their profile with zeroed stats and mastery rank 1. Increments the global artist count.

**Parameters:** none

**Returns:** `(ok true)` or `ERR-ARTIST-REGISTERED`

```clarity
(contract-call? .artHub register-digital-artist)
```

---

### `establish-art-project`

Creates a new commission project for the calling artist. Validates that piece count is positive, the deadline is a future block height, and the medium style string is at most 20 characters. Commission value is calculated automatically.

| Parameter | Type | Description |
|---|---|---|
| `piece-count` | uint | Number of artwork pieces required to complete the project |
| `completion-deadline` | uint | Bitcoin burn block height by which all pieces must be delivered |
| `medium-style` | (string-ascii 20) | Art medium or style label, e.g. `"oil-painting"` or `"pixel-art"` |

**Returns:** `(ok project-ref)` — the new project's reference number, or an error code.

```clarity
(contract-call? .artHub establish-art-project u5 u850000 "digital-illustration")
```

---

### `deliver-artwork-batch`

Records a batch of delivered pieces against an open project. Updates the artist's creativity score, submission count, last submission block, and mastery rank. If the total delivered meets or exceeds the requirement, the project is marked concluded and an accolade is granted automatically.

| Parameter | Type | Description |
|---|---|---|
| `project-ref` | uint | Reference number of the target project |
| `piece-quantity` | uint | Number of pieces being submitted in this batch |

**Returns:** `(ok {delivered, concluded, score})` or an error code.

```clarity
(contract-call? .artHub deliver-artwork-batch u1 u3)
```

---

### `claim-commission-payment`

Allows an artist to withdraw the commission value for a fully concluded project. The art fund must hold sufficient balance. Earnings are credited to the artist's profile.

| Parameter | Type | Description |
|---|---|---|
| `project-ref` | uint | Reference number of the concluded project to claim payment for |

**Returns:** `(ok commission-value)` — amount paid out — or an error code.

```clarity
(contract-call? .artHub claim-commission-payment u1)
```

---

## Administrative Functions

### `allocate-art-fund`

Curator-only. Adds the specified amount to the art fund balance. Must be called before artists can claim commission payments.

```clarity
(contract-call? .artHub allocate-art-fund u50000)
```

### `delegate-curator-role`

Curator-only. Transfers curator privileges to a new principal. The successor must differ from the current curator. This action is irreversible without the new curator's cooperation.

```clarity
(contract-call? .artHub delegate-curator-role 'SP2ABC...XYZ)
```

---

## Read-Only Functions

| Function | Parameters | Returns |
|---|---|---|
| `query-artist-record` | `artist: principal` | Full artist profile map entry or `none` |
| `query-project-record` | `artist: principal, project-ref: uint` | Full project map entry or `none` |
| `query-artist-accolades` | `artist: principal` | List of accolade strings or `none` |
| `query-hub-statistics` | none | `{community-size, fund-balance}` |

---

## Scoring & Ranking

### Commission Value Formula

Commission value is computed by the private `estimate-commission-value` function:

```
commission-value = 100 * (piece-count / 100)
```

Due to integer division this effectively pays 1 token unit per piece for piece counts that are multiples of 100, and rounds down otherwise. Ensure piece counts are set with this in mind.

### Creativity Score

Each submitted piece contributes 10 points to the artist's cumulative creativity score:

```
score-increment = piece-quantity * 10
```

### Mastery Rank

Mastery rank is recalculated on every delivery and grows with the creativity score:

```
mastery-rank = 1 + (creativity-score / 1000)
```

An artist reaches rank 2 after accumulating 1,000 score points (100 pieces), rank 3 at 2,000 points, and so on.

---

## Block Height Deadlines

All deadlines are expressed in Bitcoin burn block height (`burn-block-height`), not Unix timestamps. This is standard practice in Clarity 2+ after the deprecation of `get-block-info?`.

| Desired Duration | Approximate Block Count | Notes |
|---|---|---|
| 1 day | ~144 blocks | Bitcoin targets one block every ~10 minutes |
| 1 week | ~1,008 blocks | |
| 1 month | ~4,320 blocks | Approximate; use conservatively |
| 3 months | ~12,960 blocks | |

To set a deadline of approximately 30 days from now, pass:

```clarity
completion-deadline: burn-block-height + 4320
```

---

## Accolades

When a project is concluded (all required pieces delivered on time), the contract automatically appends an accolade to the artist's list using the format:

```
"Completed " + art-medium   (max 30 chars total)
```

Each artist can hold a maximum of **10 accolades**. Once the list is full, further accolade grants will panic. Ensure `medium-style` values are chosen so that the prefixed string stays within 30 characters.

---

## Security Considerations

- Only the registered `gallery-curator` can call `allocate-art-fund` and `delegate-curator-role`.
- Artists can only submit against their own projects; `project-ref` is scoped to the caller's principal.
- Payments are only released for concluded projects, preventing partial-work payouts.
- The art fund must be pre-funded by the curator before any claims can succeed.
- Integer division in `estimate-commission-value` can produce zero for small piece counts. Test payment values before deploying with real funds.
- Accolade list overflow will runtime-panic. Keep the number of completed projects per artist below 10 or extend the list size in a future version.

---

## Deployment Checklist

1. Deploy `artHub.clar` to the target Stacks network (mainnet or testnet).
2. Call `allocate-art-fund` to seed the contract with payment reserves.
3. Share the contract address with artists so they can call `register-digital-artist`.
4. Artists create projects with `establish-art-project` using `burn-block-height`-relative deadlines.
5. Artists deliver work incrementally via `deliver-artwork-batch`.
6. On project conclusion, artists call `claim-commission-payment` to withdraw earnings.