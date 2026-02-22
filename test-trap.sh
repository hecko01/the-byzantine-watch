#!/bin/bash
source .env

echo "🧪 Testing The Byzantine Watch..."
echo "Contract: 0x12e2F9FB6544D42240d646A6d0ec34D70CbC024A"
echo "Your address: $WALLET_ADDRESS"
echo ""

# Check if contract is owner by you
OWNER=$(cast call 0x12e2F9FB6544D42240d646A6d0ec34D70CbC024A "owner()(address)" --rpc-url $HOODI_RPC_URL)
echo "Contract owner: $OWNER"

if [ "${OWNER,,}" == "${WALLET_ADDRESS,,}" ]; then
    echo "✅ Owner matches your address!"
else
    echo "⚠️  Owner doesn't match - but that's okay"
fi

echo ""
echo "🎯 Your trap is ready to catch LP positions!"
echo "To set a trap, you would call:"
echo "setTrap(tokenId, watchPeriod, priceTrigger, externalTrigger, triggerType)"
echo ""
echo "Example: setTrap(123, 86400, 0, 0, 0) - Watch token 123 for 1 day"
