
# 📡 SubscriptionNexus

**SubscriptionNexus** is a decentralized Clarity smart contract that enables real-time, dynamic subscription-based service billing. It supports flexible prepaid payment streams, billing suspension/resumption, account credit management, and transparent settlement mechanisms between providers and subscribers.

---

## 🔧 Features

* 🔄 **Dynamic Subscription Billing**: Calculate and deduct charges based on time used and rate.
* 💰 **Credit-Based Prepayment**: Providers prepay to initiate services for subscribers.
* ⏸️ **Billing Suspension & Resumption**: Temporarily pause billing and adjust the schedule.
* 🧾 **Billing Settlement & Refunds**: Accurate billing on termination and refund unused funds.
* 📊 **Subscription Metrics**: Track active subscriptions and services provided.
* 🔍 **Transparent Auditing**: Query functions for all key records (subscriptions, credits, metrics).

---

## 🗂️ Contract Structure

### 📌 Constants

| Constant        | Description                                               |
| --------------- | --------------------------------------------------------- |
| `SERVICE_ADMIN` | Default admin (set as `tx-sender`)                        |
| `ERR_*`         | Standardized error codes for all major failure conditions |

### 🧾 Data Maps

* `service-subscriptions`: Holds all subscription records.
* `account-credits`: Tracks credit balances for all principals.
* `provider-service-catalog`: Maps providers to their created services.
* `subscriber-service-list`: Tracks subscriptions per subscriber.
* `user-subscription-metrics`: Summary stats per user.

---

## 🚀 Functions

### 💳 Credit Management

* `add-credits(amount)`: Deposit funds to user's credit balance.
* `withdraw-credits(amount)`: Withdraw from user’s credit balance.

### 📡 Subscription Lifecycle

* `activate-subscription(subscriber, rate, prepaid, cycle-duration?)`: Create a new subscription.
* `terminate-subscription(subscription-id)`: Settle billing and deactivate service.
* `extend-subscription(subscription-id, additional-prepayment)`: Top-up an existing subscription.

### 🧮 Billing Logic

* `process-billing(subscription-id)`: Compute and allocate charges for usage.
* `suspend-billing(subscription-id)`: Temporarily pause billing.
* `resume-billing(subscription-id)`: Resume suspended billing with adjusted time.

### 📊 Data Queries (Read-only)

* `get-subscription-info(subscription-id)`
* `get-credit-balance(account-holder)`
* `get-user-metrics(user)`
* `get-provider-service(provider, index)`
* `get-subscriber-service(subscriber, index)`
* `calculate-outstanding-charges(subscription-id)`
* `get-total-subscriptions()`
* `has-cycle-ended(subscription-id)`
* `get-time-reference()`

---

## 🔐 Access Control

* Only the **provider** who created the subscription can:

  * Process billing
  * Suspend/resume/terminate a subscription
  * Extend prepayment on a subscription

---

## 📈 Example Usage

1. **Add Credits**:

   ```clojure
   (add-credits u10000)
   ```

2. **Activate Subscription**:

   ```clojure
   (activate-subscription 'SP123...ABC u10 u1000 (some u5000))
   ```

3. **Process Billing**:

   ```clojure
   (process-billing u1)
   ```

4. **Suspend and Resume**:

   ```clojure
   (suspend-billing u1)
   (resume-billing u1)
   ```

5. **Terminate and Refund**:

   ```clojure
   (terminate-subscription u1)
   ```