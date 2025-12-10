## Sūrya's Description Report

### Files Description Table

| File Name                                                | SHA-1 Hash                               |
| -------------------------------------------------------- | ---------------------------------------- |
| SolidityLearning\contracts\ERC20\BasicProxy.sol          | c5b953de6a22df2d983f5bbe7ed97d27c72ada07 |
| SolidityLearning\contracts\ERC20\CoolToken.sol           | 13b6705ea79f91606b197e35badff1636ff5a4a0 |
| SolidityLearning\contracts\ERC20\ERC20Base.sol           | b401d998ea3522b33fc0e9fc60eda5456b5a5bc1 |
| SolidityLearning\contracts\ERC20\Tradeable.sol           | 5b50d2f2e88cce9e25cfeda52559a5deb1056f4a |
| SolidityLearning\contracts\ERC20\Voting.sol              | 58f62176f2a71d89e9f71dd2b263229afa7ccf72 |
| SolidityLearning\contracts\ERC20\VotingLinkedListLib.sol | 9bad7e1e2d9b451ee4a8f0762d0f7f2ef5d6cfe8 |

### Contracts Description Table

|        Contract         |        Type        |                                         Bases                                          |                |                  |
| :---------------------: | :----------------: | :------------------------------------------------------------------------------------: | :------------: | :--------------: |
|            └            | **Function Name**  |                                     **Visibility**                                     | **Mutability** |  **Modifiers**   |
|                         |                    |                                                                                        |                |                  |
|     **BasicProxy**      |   Implementation   |                                      ERC1967Proxy                                      |                |                  |
|            └            |   <Constructor>    |                                       Public ❗️                                        |       🛑       |   ERC1967Proxy   |
|                         |                    |                                                                                        |                |                  |
|      **CoolToken**      |   Implementation   |                                         Voting                                         |                |                  |
|            └            |   <Constructor>    |                                       Public ❗️                                        |       🛑       |       NO❗️       |
|            └            |     initialize     |                                       Public ❗️                                        |       🛑       |   initializer    |
|            └            | \_authorizeUpgrade |                                      Internal 🔒                                       |       🛑       |    onlyOwner     |
|                         |                    |                                                                                        |                |                  |
|      **ERC20Base**      |   Implementation   | Initializable, IERC20, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable |                |                  |
|            └            | \_\_ERC20Base_init |                                      Internal 🔒                                       |       🛑       | onlyInitializing |
|            └            |        name        |                                       Public ❗️                                        |                |       NO❗️       |
|            └            |       symbol       |                                       Public ❗️                                        |                |       NO❗️       |
|            └            |      decimals      |                                       Public ❗️                                        |                |       NO❗️       |
|            └            |    totalSupply     |                                       Public ❗️                                        |                |       NO❗️       |
|            └            |     balanceOf      |                                       Public ❗️                                        |                |       NO❗️       |
|            └            |      transfer      |                                       Public ❗️                                        |       🛑       |       NO❗️       |
|            └            |     allowance      |                                       Public ❗️                                        |                |       NO❗️       |
|            └            |      approve       |                                       Public ❗️                                        |       🛑       |       NO❗️       |
|            └            |    transferFrom    |                                       Public ❗️                                        |       🛑       |       NO❗️       |
|            └            | \_authorizeUpgrade |                                      Internal 🔒                                       |       🛑       |    onlyOwner     |
|            └            |      \_update      |                                      Internal 🔒                                       |       🛑       |                  |
|            └            |     \_transfer     |                                      Internal 🔒                                       |       🛑       |                  |
|            └            |       \_mint       |                                      Internal 🔒                                       |       🛑       |                  |
|            └            |       \_burn       |                                      Internal 🔒                                       |       🛑       |                  |
|                         |                    |                                                                                        |                |                  |
|      **Tradeable**      |   Implementation   |                                       ERC20Base                                        |                |                  |
|            └            | \_\_Tradeable_init |                                      Internal 🔒                                       |       🛑       | onlyInitializing |
|            └            |       feeBps       |                                      External ❗️                                       |                |       NO❗️       |
|            └            |     setFeeBps      |                                      External ❗️                                       |       🛑       |    onlyOwner     |
|            └            |        buy         |                                      External ❗️                                       |       💵       |       NO❗️       |
|            └            |        sell        |                                      External ❗️                                       |       🛑       |   nonReentrant   |
|            └            |      burnFees      |                                      External ❗️                                       |       🛑       |       NO❗️       |
|                         |                    |                                                                                        |                |                  |
|       **Voting**        |   Implementation   |                                       Tradeable                                        |                |                  |
|            └            |  \_\_Voting_init   |                                      Internal 🔒                                       |       🛑       | onlyInitializing |
|            └            |      getNode       |                                      External ❗️                                       |                |       NO❗️       |
|            └            |    startVoting     |                                      External ❗️                                       |       🛑       |       NO❗️       |
|            └            |        vote        |                                      External ❗️                                       |       💵       |       NO❗️       |
|            └            |     endVoting      |                                      External ❗️                                       |       🛑       |       NO❗️       |
|            └            |      withdraw      |                                      External ❗️                                       |       🛑       |   nonReentrant   |
|            └            |       claim        |                                      External ❗️                                       |       🛑       |   nonReentrant   |
|                         |                    |                                                                                        |                |                  |
| **VotingLinkedListLib** |      Library       |                                                                                        |                |                  |
|            └            |      contains      |                                      Internal 🔒                                       |                |                  |
|            └            |      isEmpty       |                                      Internal 🔒                                       |                |                  |
|            └            |   getWinnerPrice   |                                      Internal 🔒                                       |                |                  |
|            └            |      getPower      |                                      Internal 🔒                                       |                |                  |
|            └            |      getNode       |                                      Internal 🔒                                       |                |                  |
|            └            |       insert       |                                      Internal 🔒                                       |       🛑       |                  |
|            └            |       update       |                                      Internal 🔒                                       |       🛑       |                  |
|            └            |       remove       |                                      Internal 🔒                                       |       🛑       |                  |
|            └            | findInsertPosition |                                      Internal 🔒                                       |                |                  |
|            └            |   \_descendList    |                                      Internal 🔒                                       |                |                  |
|            └            |    \_ascendList    |                                      Internal 🔒                                       |                |                  |
|            └            |   \_isValidPlace   |                                      Internal 🔒                                       |                |                  |
|            └            |   \_findFromHead   |                                      Internal 🔒                                       |                |                  |
|            └            |       \_link       |                                      Internal 🔒                                       |       🛑       |                  |
|            └            |      \_unlink      |                                      Internal 🔒                                       |       🛑       |                  |

### Legend

| Symbol | Meaning                   |
| :----: | ------------------------- |
|   🛑   | Function can modify state |
|   💵   | Function is payable       |
