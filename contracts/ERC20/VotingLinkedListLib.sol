// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title VotingLinkedListLib
/// @notice Sorted linked list helpers used by the Voting contract.
/// @dev All mutating functions are internal so no external caller can touch the list.
library VotingLinkedListLib {
    error NodeExists();
    error NodeNotFound();
    error InvalidPosition();
    error PowerCanNotBeZero();

    /// @notice Node stored in the linked list
    struct Node {
        uint256 price;
        uint256 power;
        uint256 prevPrice;
        uint256 nextPrice;
    }

    /// @notice List container that holds nodes and head/tail pointers
    struct List {
        mapping(uint256 => Node) nodes;
        uint256 head;
        uint256 tail;
        uint256 size;
    }

    /// @notice Check whether a node with given price exists in the list
    /// @param self List storage pointer
    /// @param price Price key to check
    /// @return True if node exists (power != 0)
    function contains(
        List storage self,
        uint256 price
    ) internal view returns (bool) {
        return self.nodes[price].power != 0;
    }

    /// @notice Check whether the list is empty
    /// @param self List storage pointer
    /// @return True if list contains no nodes
    function isEmpty(List storage self) internal view returns (bool) {
        return self.size == 0;
    }

    /// @notice Return the winning price (head of the list)
    /// @param self List storage pointer
    /// @return Price stored in head (0 if empty)
    function getWinnerPrice(List storage self) internal view returns (uint256) {
        return self.head;
    }

    /// @notice Return the aggregated power for a node identified by price
    /// @param self List storage pointer
    /// @param price Node price key
    /// @return Power of the node (0 if not present)
    function getPower(
        List storage self,
        uint256 price
    ) internal view returns (uint256) {
        return self.nodes[price].power;
    }

    function getNode(
        List storage self,
        uint256 price
    ) internal view returns (Node memory) {
        return self.nodes[price];
    }

    /// @notice Insert a new node (sorted by power) into the list
    /// @dev Reverts if node exists or power == 0. Hints may be provided to save gas.
    /// @param self List storage pointer
    /// @param price Price key for the node
    /// @param power Aggregated power for the node
    /// @param prevHint Hint for previous node price (0 if none)
    /// @param nextHint Hint for next node price (0 if none)
    function insert(
        List storage self,
        uint256 price,
        uint256 power,
        uint256 prevHint,
        uint256 nextHint
    ) internal {
        if (contains(self, price)) revert NodeExists();
        if (power == 0) revert PowerCanNotBeZero();

        (uint256 prevPrice, uint256 nextPrice) = findInsertPosition(
            self,
            power,
            prevHint,
            nextHint
        );

        _link(self, price, power, prevPrice, nextPrice);
        self.size++;
    }

    /// @notice Update an existing node's power and reposition it
    /// @dev Reverts if node not found or power == 0.
    /// @param self List storage pointer
    /// @param price Price key for the node
    /// @param power New aggregated power
    /// @param prevHint Hint for previous node price (0 if none)
    /// @param nextHint Hint for next node price (0 if none)
    function update(
        List storage self,
        uint256 price,
        uint256 power,
        uint256 prevHint,
        uint256 nextHint
    ) internal {
        if (!contains(self, price)) revert NodeNotFound();
        if (power == 0) revert PowerCanNotBeZero();

        _unlink(self, price);
        (uint256 prevPrice, uint256 nextPrice) = findInsertPosition(
            self,
            power,
            prevHint,
            nextHint
        );
        _link(self, price, power, prevPrice, nextPrice);
    }

    /// @notice Remove node identified by price from the list
    /// @dev Reverts if node not found.
    /// @param self List storage pointer
    /// @param price Price key for the node to remove
    function remove(List storage self, uint256 price) internal {
        if (!contains(self, price)) revert NodeNotFound();
        _unlink(self, price);
        delete self.nodes[price];
        self.size--;
    }

    /// @notice Find insertion position for a node with given power using hints
    /// @dev Returns (prevPrice, nextPrice) where node should be placed.
    /// @param self List storage pointer
    /// @param power Power to place
    /// @param prevHint Hint for previous node price (0 if none)
    /// @param nextHint Hint for next node price (0 if none)
    /// @return prevPrice Price of previous node (0 if new head)
    /// @return nextPrice Price of next node (0 if new tail)
    function findInsertPosition(
        List storage self,
        uint256 power,
        uint256 prevHint,
        uint256 nextHint
    ) internal view returns (uint256 prevPrice, uint256 nextPrice) {
        bool prevValid = (prevHint == 0) || contains(self, prevHint);
        bool nextValid = (nextHint == 0) || contains(self, nextHint);

        if (!prevValid && !nextValid) {
            return _findFromHead(self, power);
        }

        if (prevValid && !nextValid) {
            if (prevHint == 0) {
                return _findFromHead(self, power);
            }
            return _descendList(self, power, prevHint);
        }

        if (!prevValid && nextValid) {
            if (nextHint == 0) {
                return _findFromHead(self, power);
            }
            return _ascendList(self, power, nextHint);
        }

        if (_isValidPlace(self, power, prevHint, nextHint)) {
            return (prevHint, nextHint);
        }

        if (prevHint != 0 && self.nodes[prevHint].power >= power) {
            return _descendList(self, power, prevHint);
        }

        if (nextHint != 0 && self.nodes[nextHint].power <= power) {
            return _ascendList(self, power, nextHint);
        }

        return _findFromHead(self, power);
    }

    /// @dev Walk the list forward from `start` until the correct insertion point is found.
    function _descendList(
        List storage self,
        uint256 power,
        uint256 start
    ) internal view returns (uint256 prevPrice, uint256 nextPrice) {
        prevPrice = start;
        nextPrice = self.nodes[start].nextPrice;

        while (nextPrice != 0 && self.nodes[nextPrice].power >= power) {
            prevPrice = nextPrice;
            nextPrice = self.nodes[nextPrice].nextPrice;
        }
    }

    /// @dev Walk the list backward from `start` until the correct insertion point is found.
    function _ascendList(
        List storage self,
        uint256 power,
        uint256 start
    ) internal view returns (uint256 prevPrice, uint256 nextPrice) {
        nextPrice = start;
        prevPrice = self.nodes[start].prevPrice;

        while (prevPrice != 0 && self.nodes[prevPrice].power < power) {
            nextPrice = prevPrice;
            prevPrice = self.nodes[prevPrice].prevPrice;
        }
    }

    /// @dev Validate whether provided prev/next form a valid place for given power.
    function _isValidPlace(
        List storage self,
        uint256 power,
        uint256 prevPrice,
        uint256 nextPrice
    ) internal view returns (bool) {
        if (prevPrice == 0 && nextPrice == 0) return isEmpty(self);
        else if (prevPrice == 0 && nextPrice != self.head) return false;
        else if (nextPrice == 0 && prevPrice != self.tail) return false;
        else {
            Node memory prev = self.nodes[prevPrice];
            Node memory next = self.nodes[nextPrice];
            return
                prev.nextPrice == nextPrice &&
                prev.power >= power &&
                next.power <= power;
        }
    }

    /// @dev Scan the list from the head to find insertion point.
    function _findFromHead(
        List storage self,
        uint256 power
    ) internal view returns (uint256 prevPrice, uint256 nextPrice) {
        nextPrice = self.head;
        prevPrice = 0;

        while (nextPrice != 0 && self.nodes[nextPrice].power >= power) {
            prevPrice = nextPrice;
            nextPrice = self.nodes[nextPrice].nextPrice;
        }

        return (prevPrice, nextPrice);
    }

    /// @dev Link a new node into the list; does not update size.
    function _link(
        List storage self,
        uint256 price,
        uint256 power,
        uint256 prevPrice,
        uint256 nextPrice
    ) internal {
        self.nodes[price] = Node(price, power, prevPrice, nextPrice);

        if (prevPrice == 0) self.head = price;
        else self.nodes[prevPrice].nextPrice = price;

        if (nextPrice == 0) self.tail = price;
        else self.nodes[nextPrice].prevPrice = price;
    }

    /// @dev Unlink a node from the list; does not delete storage entry.
    function _unlink(List storage self, uint256 price) internal {
        Node storage n = self.nodes[price];

        if (n.prevPrice == 0) self.head = n.nextPrice;
        else self.nodes[n.prevPrice].nextPrice = n.nextPrice;

        if (n.nextPrice == 0) self.tail = n.prevPrice;
        else self.nodes[n.nextPrice].prevPrice = n.prevPrice;
    }
}
