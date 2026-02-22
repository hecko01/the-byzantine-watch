// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "v3-periphery/interfaces/INonfungiblePositionManager.sol";

/**
 * @title ByzantineExit
 * @dev The primary trap of The Byzantine Watch - monitors LP positions and executes exits on triggers
 */
contract ByzantineExit is Ownable, ReentrancyGuard {
    // ==================== STRUCTS ====================
    struct WatchedPosition {
        uint256 tokenId;
        address owner;
        uint256 unlockTime;
        uint256 priceTrigger;
        uint256 externalTrigger;
        uint256 createdAt;
        bool active;
        TriggerType triggerType;
    }

    enum TriggerType {
        TIME_ONLY,
        PRICE_ONLY,
        EXTERNAL_ONLY,
        TIME_AND_PRICE,
        TIME_AND_EXTERNAL,
        PRICE_AND_EXTERNAL,
        ALL_VECTORS
    }

    // ==================== STATE VARIABLES ====================
    INonfungiblePositionManager public immutable positionManager;
    
    mapping(uint256 => WatchedPosition) public watchtower;
    mapping(address => uint256[]) public citizenWatches;
    
    uint256 public constant MIN_WATCH_PERIOD = 1 hours;
    uint256 public constant MAX_WATCH_PERIOD = 365 days;
    
    // Events
    event PositionWatched(uint256 indexed tokenId, address indexed owner, TriggerType triggerType);
    event TrapTriggered(uint256 indexed tokenId, address indexed owner, string trigger);
    event PositionUnwound(uint256 indexed tokenId, uint256 amount0, uint256 amount1);
    event PositionReleased(uint256 indexed tokenId, address indexed owner);

    // ==================== CONSTRUCTOR ====================
    constructor(address _positionManager) Ownable(msg.sender) {
        positionManager = INonfungiblePositionManager(_positionManager);
    }

    // ==================== CORE FUNCTIONS ====================
    function setTrap(
        uint256 _tokenId,
        uint256 _watchPeriod,
        uint256 _priceTrigger,
        uint256 _externalTrigger,
        TriggerType _triggerType
    ) external nonReentrant {
        // Validate period
        if (_watchPeriod > 0) {
            require(_watchPeriod >= MIN_WATCH_PERIOD && _watchPeriod <= MAX_WATCH_PERIOD, "Invalid watch period");
        }
        
        // Transfer NFT to the watchtower
        positionManager.transferFrom(msg.sender, address(this), _tokenId);
        
        // Set the trap
        watchtower[_tokenId] = WatchedPosition({
            tokenId: _tokenId,
            owner: msg.sender,
            unlockTime: _watchPeriod > 0 ? block.timestamp + _watchPeriod : 0,
            priceTrigger: _priceTrigger,
            externalTrigger: _externalTrigger,
            createdAt: block.timestamp,
            active: true,
            triggerType: _triggerType
        });
        
        citizenWatches[msg.sender].push(_tokenId);
        
        emit PositionWatched(_tokenId, msg.sender, _triggerType);
    }

    function checkTrap(uint256 _tokenId) external nonReentrant {
        WatchedPosition storage pos = watchtower[_tokenId];
        require(pos.active, "Trap not active");
        
        bool shouldTrigger = false;
        string memory triggerReason = "";
        
        // Check time trigger
        if (pos.unlockTime > 0 && block.timestamp >= pos.unlockTime) {
            shouldTrigger = true;
            triggerReason = "TIME_VECTOR";
        }
        
        // Check price trigger (simplified - always false for now)
        if (!shouldTrigger && pos.priceTrigger > 0) {
            // Price check would go here
            // For now, just a placeholder
        }
        
        require(shouldTrigger, "Trap conditions not met");
        
        emit TrapTriggered(_tokenId, pos.owner, triggerReason);
        
        // Execute the trap - unwind position
        _unwindPosition(_tokenId);
    }

    function releasePosition(uint256 _tokenId) external nonReentrant {
        WatchedPosition storage pos = watchtower[_tokenId];
        require(pos.active, "Trap not active");
        require(msg.sender == pos.owner, "Not the watch owner");
        
        // Check if time condition is met for manual release
        if (pos.unlockTime > 0) {
            require(block.timestamp >= pos.unlockTime, "Watch period not complete");
        }
        
        // Return the NFT
        positionManager.transferFrom(address(this), pos.owner, _tokenId);
        pos.active = false;
        
        emit PositionReleased(_tokenId, pos.owner);
    }

    // ==================== INTERNAL FUNCTIONS ====================
    function _unwindPosition(uint256 _tokenId) internal {
        WatchedPosition storage pos = watchtower[_tokenId];
        
        // Get position info using the correct return types
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,
            
        ) = positionManager.positions(_tokenId);
        
        uint256 amount0 = 0;
        uint256 amount1 = 0;
        
        // Decrease liquidity if any exists
        if (liquidity > 0) {
            INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseParams = 
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: _tokenId,
                    liquidity: liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });
            
            (amount0, amount1) = positionManager.decreaseLiquidity(decreaseParams);
        }
        
        // Collect all fees
        INonfungiblePositionManager.CollectParams memory collectParams = 
            INonfungiblePositionManager.CollectParams({
                tokenId: _tokenId,
                recipient: pos.owner,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });
        
        positionManager.collect(collectParams);
        
        // Transfer any remaining tokens from decreaseLiquidity
        if (amount0 > 0) {
            IERC20(token0).transfer(pos.owner, amount0);
        }
        if (amount1 > 0) {
            IERC20(token1).transfer(pos.owner, amount1);
        }
        
        pos.active = false;
        
        emit PositionUnwound(_tokenId, amount0, amount1);
    }

    // ==================== VIEW FUNCTIONS ====================
    function getWatchedPositions(address _citizen) external view returns (uint256[] memory) {
        return citizenWatches[_citizen];
    }

    function isPositionWatched(uint256 _tokenId) external view returns (bool) {
        return watchtower[_tokenId].active;
    }
}
