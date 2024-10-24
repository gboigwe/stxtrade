# STX-Derivatives Platform Smart Contracts

A decentralized derivatives trading platform built on the Stacks blockchain, enabling users to trade futures and options using STX as collateral.

## Overview

This project implements smart contracts for a derivatives trading platform on the Stacks blockchain. The platform enables users to:
- Trade perpetual futures with leverage
- Create and trade options contracts
- Manage STX collateral
- Participate in automated liquidations

### Key Features

- **Collateral Management**
  - STX deposit and withdrawal
  - Dynamic collateral ratio calculations
  - Automated margin calls

- **Trading Features**
  - Perpetual futures trading
  - Options contract creation and trading
  - Position management
  - Automated liquidation system

- **Risk Management**
  - Price oracle integration
  - Liquidation mechanisms
  - Emergency shutdown capabilities
  - Circuit breakers

## Smart Contract Architecture

### Core Contracts

1. **vault-manager.clar**
   - Manages user deposits and withdrawals
   - Tracks collateral ratios
   - Handles margin requirements

2. **perpetual-futures.clar**
   - Implements perpetual futures trading logic
   - Manages positions and leverage
   - Handles funding rate calculations

3. **options-engine.clar**
   - Options creation and trading
   - Premium calculations
   - Exercise and settlement logic

4. **liquidation-engine.clar**
   - Monitors position health
   - Executes liquidations
   - Manages liquidation incentives

5. **price-oracle.clar**
   - Integrates with price feeds
   - Provides secure price data
   - Implements safety checks

## Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Basic understanding of Clarity language
- Hiro Wallet for testing

### Installation

```bash
# Clone the repository
git clone https://github.com/gboigwe/stxtrade

# Navigate to project directory
cd stx-derivatives-platform

# Install dependencies
clarinet requirements

# Run tests
clarinet test
```

### Contract Deployment

1. Configure your network in `Clarinet.toml`
2. Deploy to testnet:
```bash
clarinet deploy --network testnet
```

## Testing

The project includes comprehensive tests for all major functionalities:

```clarity
;; Example test structure
(contract-call? .vault-manager deposit-collateral u1000)
(contract-call? .perpetual-futures open-position 'long u100 u10)
```

Run tests using:
```bash
clarinet test
```

## Contract Interactions

### Depositing Collateral
```clarity
(contract-call? .vault-manager deposit-collateral amount)
```

### Opening a Position
```clarity
(contract-call? .perpetual-futures open-position
    position-type   ;; 'long or 'short
    size           ;; position size
    leverage)      ;; leverage amount
```

### Creating an Option
```clarity
(contract-call? .options-engine create-option
    strike-price
    expiry
    option-type)   ;; 'call or 'put
```

## Security Considerations

- All contracts implement access controls
- Emergency shutdown mechanisms included
- Rate limiting on critical functions
- Price oracle safety checks
- Liquidation thresholds and delays

## Development Roadmap

1. **Phase 1: Core Infrastructure**
   - Basic vault management
   - Collateral handling
   - Position management

2. **Phase 2: Trading Features**
   - Perpetual futures implementation
   - Basic options trading
   - Liquidation mechanism

3. **Phase 3: Advanced Features**
   - Complex options strategies
   - Advanced risk management
   - Oracle integration

4. **Phase 4: Testing & Deployment**
   - Comprehensive testing
   - Testnet deployment
   - Security audit
   - Mainnet preparation

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## Testing on Hiro Platform

1. Deploy contracts using Clarinet
2. Access contracts via Hiro Platform
3. Test functionality using Hiro Wallet
4. Monitor contract interactions

## Contact

- Project Link: [https://github.com/gboigwe/stxtrade](https://github.com/gboigwe/stxtrade)
