source .env

forge script script/Deploy.s.sol:Deploy \
--rpc-url $RPC_URL \
--broadcast \
--verify \
--etherscan-api-key $ETHERSCAN_API_KEY \
--verifier-url https://api-sepolia.etherscan.io/api \
--private-key $PRIVATE_KEY