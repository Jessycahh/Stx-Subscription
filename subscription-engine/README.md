# Subscription Service Smart Contract

## Overview
This smart contract implements a comprehensive subscription management system on the Stacks blockchain. It allows for tiered subscriptions, upgrades/downgrades, refunds, and administrative controls. The system is designed to handle subscription lifecycles with support for various subscription tiers and flexible payment management.

## Features
- Multiple subscription tier support
- Automated subscription lifecycle management
- Upgrade and downgrade functionality
- Refund system with configurable time windows
- Administrative controls and configuration
- Credit balance tracking for downgrades
- Comprehensive error handling

## Contract Configuration

### Default Values
- Minimum subscription cost: 100 microSTX
- Standard subscription duration: 30 days (2,592,000 blocks)
- Maximum refund window: 3 days (259,200 blocks)
- Plan change fee: 1 STX (1,000,000 microSTX)

### Default Subscription Tiers
1. Basic Tier
   - Cost: 50 STX
   - Duration: 30 days
   - Features: Basic Platform Access, Standard Customer Support, Core Feature Set
   - Refundable: Yes

2. Premium Tier
   - Cost: 100 STX
   - Duration: 30 days
   - Features: Premium Platform Access, 24/7 Priority Support, Complete Feature Set, Advanced Analytics Dashboard
   - Refundable: Yes

## Function Reference

### Public Functions

#### Subscription Management
1. `subscribe-to-plan(selected-tier-name: string-ascii)`
   - Initiates a new subscription for the caller
   - Requires payment in STX
   - Cannot be called with active subscription

2. `upgrade-subscription-tier(new-tier-name: string-ascii)`
   - Upgrades existing subscription to a higher tier
   - Calculates and charges prorated difference
   - Includes plan change fee

3. `downgrade-subscription-tier(new-tier-name: string-ascii)`
   - Downgrades subscription to a lower tier
   - Calculates and stores credit for unused time
   - Charges plan change fee

4. `request-subscription-refund(refund-justification: string-ascii)`
   - Processes refund request within refund window
   - Calculates prorated refund amount
   - Requires active subscription with refunds enabled

### Administrative Functions

1. `create-subscription-tier(tier-name: string-ascii, tier-cost: uint, tier-duration: uint, tier-features: list, tier-level: uint, allows-refunds: bool)`
   - Creates new subscription tier
   - Restricted to contract administrator
   - Validates all input parameters

2. `update-refund-window(new-refund-window: uint)`
   - Updates the maximum period for refund eligibility
   - Restricted to contract administrator

3. `update-plan-change-fee(updated-fee: uint)`
   - Updates the fee charged for changing subscription tiers
   - Restricted to contract administrator

### Read-Only Functions

1. `get-subscriber-details(subscriber-address: principal)`
   - Returns complete subscription information for an address

2. `get-subscription-tier-details(subscription-tier-name: string-ascii)`
   - Returns configuration details for a subscription tier

3. `calculate-subscription-time-remaining(subscriber-address: principal)`
   - Returns remaining time in current subscription period

4. `calculate-eligible-refund-amount(subscriber-address: principal)`
   - Calculates potential refund amount for current subscription

## Error Codes

| Code | Description |
|------|-------------|
| u100 | Unauthorized access attempt |
| u101 | Subscription already exists |
| u102 | No active subscription found |
| u103 | Insufficient STX balance |
| u104 | Invalid subscription type |
| u105 | Subscription expired |
| u106 | Invalid refund amount |
| u107 | Identical plan upgrade attempt |
| u108 | Refund period expired |
| u109 | Invalid plan change |
| u110 | Invalid input parameters |

## Data Structures

### SubscriberDetails
```clarity
{
    subscription-active: bool,
    subscription-start-timestamp: uint,
    subscription-end-timestamp: uint,
    current-subscription-plan: (string-ascii 20),
    last-payment-amount: uint,
    subscription-credit-balance: uint
}
```

### SubscriptionTierConfiguration
```clarity
{
    plan-cost: uint,
    plan-duration: uint,
    plan-features: (list 10 (string-ascii 50)),
    plan-tier-level: uint,
    refunds-enabled: bool
}
```

### CustomerRefundHistory
```clarity
{
    refund-amount: uint,
    refund-reason: (string-ascii 50)
}
```

## Security Considerations

1. Administrative Functions
   - All administrative functions are protected by principal verification
   - Only the contract administrator can modify critical parameters
   - Changes to subscription tiers don't affect existing subscriptions

2. Financial Operations
   - All STX transfers are validated before execution
   - Refund calculations include safeguards against exploitation
   - Upgrade/downgrade operations include proper value calculations

3. Input Validation
   - All public functions include comprehensive input validation
   - String inputs have appropriate length restrictions
   - Numeric inputs are checked for valid ranges

## Integration Guide

### Prerequisites
- Stacks wallet with sufficient STX balance
- Administrative access (for admin functions)

### Basic Integration Steps
1. Deploy the contract to the Stacks blockchain
2. Initialize default subscription tiers
3. Configure refund window and plan change fees
4. Begin accepting subscriptions

### Example Usage
```clarity
;; Subscribe to basic tier
(contract-call? .subscription-service subscribe-to-plan "basic-tier")

;; Upgrade to premium tier
(contract-call? .subscription-service upgrade-subscription-tier "premium-tier")

;; Request refund
(contract-call? .subscription-service request-subscription-refund "Service not needed")
```

## Maintenance and Upgrades
- The contract includes configuration options for key parameters
- New subscription tiers can be added without contract upgrades
- Fee structures can be adjusted by the administrator
- Refund policies can be modified through administrative functions