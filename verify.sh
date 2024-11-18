forge verify-contract "0x938f60c642107d50F28938e9b121583f18DA5092" BaseLogoNFT \
    --constructor-args-path args.json \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --chain-id $CHAIN_ID


# forge verify-contract \
#     --chain-id 8453 \
#     --compiler-version v0.8.26 \
#     --constructor-args $(cast abi-encode "constructor(address)" "0x7Bc1C072742D8391817EB4Eb2317F98dc72C61dB") \
#     --verifier-url https://api.basescan.org/api \
#     --verifier etherscan \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --watch \
#     0x938f60c642107d50F28938e9b121583f18DA5092 \
#     src/BaseLogoNFT.sol:BaseLogoNFT \
    