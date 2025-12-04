// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract VotingLinkedList {
    error NodeExists();
    error NodeNotFound();
    error InvalidPosition();
    error PowerCanNotBeZero();

    uint256 public head;
    uint256 public tail;
    uint256 public size;

    struct Node {
        uint256 price;
        uint256 power;
        uint256 prevPrice;
        uint256 nextPrice;
    }

    mapping(uint256 => Node) public nodes;

    function contains(uint256 price) public view returns (bool) {
        return nodes[price].power != 0;
    }

    function isEmpty() public view returns (bool) {
        return size == 0;
    }

    function getWinnerPrice() public view returns (uint256) {
        return head;
    }

    function getPower(uint256 price) public view returns (uint256) {
        return nodes[price].power;
    }

    function insert(
        uint256 price,
        uint256 power,
        uint256 prevHint,
        uint256 nextHint
    ) external {
        if (contains(price)) revert NodeExists();
        require(power > 0);

        (prevHint, nextHint) = findInsertPosition(power, prevHint, nextHint);

        _link(price, power, prevHint, nextHint);
        size++;
    }

    function update(
        uint256 price,
        uint256 power,
        uint256 prevHint,
        uint256 nextHint
    ) external {
        if (!contains(price)) revert NodeNotFound();
        if (power == 0) revert PowerCanNotBeZero();
        _unlink(price);
        (prevHint, nextHint) = findInsertPosition(power, prevHint, nextHint);
        _link(price, power, prevHint, nextHint);
    }

    function remove(uint256 price) public {
        if (!contains(price)) revert NodeNotFound();
        _unlink(price);
        delete nodes[price];
        size--;
    }

    function findInsertPosition(
        uint256 power,
        uint256 prevHint,
        uint256 nextHint
    ) public view returns (uint256 prevPrice, uint256 nextPrice) {
        bool prevValid = (prevHint == 0) || contains(prevHint);
        bool nextValid = (nextHint == 0) || contains(nextHint);

        if (!prevValid && !nextValid) {
            return _findFromHead(power);
        }

        if (prevValid && !nextValid) {
            if (prevHint == 0) {
                return _findFromHead(power);
            }
            return _descendList(power, prevHint);
        }

        if (!prevValid && nextValid) {
            if (nextHint == 0) {
                return _findFromHead(power);
            }
            return _ascendList(power, nextHint);
        }

        if (_isValidPlace(power, prevHint, nextHint)) {
            return (prevHint, nextHint);
        }

        if (prevHint != 0 && nodes[prevHint].power >= power) {
            return _descendList(power, prevHint);
        }

        if (nextHint != 0 && nodes[nextHint].power <= power) {
            return _ascendList(power, nextHint);
        }

        return _findFromHead(power);
    }

    function _descendList(
        uint256 power,
        uint256 start
    ) internal view returns (uint256 prevPrice, uint256 nextPrice) {
        prevPrice = start;
        nextPrice = nodes[start].nextPrice;

        while (nextPrice != 0 && nodes[nextPrice].power >= power) {
            prevPrice = nextPrice;
            nextPrice = nodes[nextPrice].nextPrice;
        }
    }

    function _ascendList(
        uint256 power,
        uint256 start
    ) internal view returns (uint256 prevPrice, uint256 nextPrice) {
        nextPrice = start;
        prevPrice = nodes[start].prevPrice;

        while (prevPrice != 0 && nodes[prevPrice].power < power) {
            nextPrice = prevPrice;
            prevPrice = nodes[prevPrice].prevPrice;
        }
    }

    function _isValidPlace(
        uint256 power,
        uint256 prevPrice,
        uint256 nextPrice
    ) internal view returns (bool) {
        if (prevPrice == 0 && nextPrice == 0) return isEmpty();
        else if (prevPrice == 0 && nextPrice != head) return false;
        else if (nextPrice == 0 && prevPrice != tail) return false;
        else {
            Node memory prev = nodes[prevPrice];
            Node memory next = nodes[nextPrice];
            return
                prev.nextPrice == nextPrice &&
                prev.power >= power &&
                next.power <= power;
        }
    }

    function _findFromHead(
        uint256 power
    ) internal view returns (uint256 prevPrice, uint256 nextPrice) {
        nextPrice = head;
        prevPrice = 0;

        while (nextPrice != 0 && nodes[nextPrice].power >= power) {
            prevPrice = nextPrice;
            nextPrice = nodes[nextPrice].nextPrice;
        }

        return (prevPrice, nextPrice);
    }

    function _link(
        uint256 price,
        uint256 power,
        uint256 prevPrice,
        uint256 nextPrice
    ) internal {
        nodes[price] = Node(price, power, prevPrice, nextPrice);

        if (prevPrice == 0) head = price;
        else nodes[prevPrice].nextPrice = price;

        if (nextPrice == 0) tail = price;
        else nodes[nextPrice].prevPrice = price;
    }

    function _unlink(uint256 price) internal {
        Node storage n = nodes[price];

        if (n.prevPrice == 0) head = n.nextPrice;
        else nodes[n.prevPrice].nextPrice = n.nextPrice;

        if (n.nextPrice == 0) tail = n.prevPrice;
        else nodes[n.nextPrice].prevPrice = n.prevPrice;
    }
}
