. ./.env

forge script \
    --private-key $PRIVATE_KEY \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    --etherscan-api-key $BLOCK_EXPLORER_API_KEY \
    --verify \
    src/script/Deploy.s.sol