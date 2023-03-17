# Overview

https://liquorice.gitbook.io/docs/

The key goal of the project is to provide an onchain MEV-aware trading space with the implementation of brokerage type of execution in DEFI. The approach differs from existing AMM pools and onchain/offchain orderbooks. 

Core audience:

-Traders in DEFI who want to be able to swap coins onchain with the usage of cryptocurrency wallets such as metamask. Small users benefit from tight spread due to efficient liquidity stimulation which gives makers a good reason to price big volumes very close to the market price. A special interest may come from liquidators or other participants who want to execute big volume automatically and instantly without waiting for a good OTC trade as liquorice provides stuimulus for makers to price big clips constantly in the market similar to traditional FX brokerages or order book exchanges. Which gives an edge over AMM or RFQ based protocols 

-Makert makers. Especially those who have high vip tiers on centralized exchnages such as binance. Protocol is largely designed to give an easy way for CEXs market makers to price DEFI users

-Liquidity providers who want to supply liquidity to market makers and earn a fee in return

There are three key ideas in the project: 

1) Auction based system. Market makers first get to see the matched trades so that they have an opportunity to cancel those which they see as toxic (latency trades, sandwich attacks etc). Makers can basically wait a bit to see where the market is to make sure that they can execute in profit and only then approve. There is an economic system in place to prevent makers from abusing auction system and we are looking to use account abstraction for this purpose. 

![image](https://user-images.githubusercontent.com/105652074/225651342-ae25ff0b-8f26-49dc-8c51-78cd86d6e0a2.png)

2) Separation of market makers and LPs. For example, AMM pools suffer from the fact that most LPs there are highly likely to lose due to impairment loss. We split the roles so that proffesional users can price the market and carry market risk while regular LPs can provide single coins as colateral for makers to earn a fee. 

![image](https://user-images.githubusercontent.com/105652074/225652434-6c00afdd-9004-4bc5-9705-838d6176159b.png)

3) Onchain protocol. We ensure that all trades are filled in accordance with onchain data. In current implementation we are using an oracle. But all makers are safe from oracle price manipulation thanks to auction system itself. Oracle price is first pushed onchain and makers can decide on canceling the trade in accordance with onchain data. Takers may avoid oracle manipulation risk by providing maximum price at which they are ready to swap. Oracle mechanism also helps with gas costs and speed as makers issue a "commitment" instead of constantly replacing limit orders according to market price change. 
