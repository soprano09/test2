// SPDX-License-Identifier:	UNLICENSED

pragma solidity ^0.8.0;

import "./Constants.sol";
import "./Base.sol";
import "./BaseSpells.sol";
import "./BaseLoot.sol";
import "./Hero.sol";
import "./CultureCoinV1M0m1.sol";
import "./Legion.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract TimeCube is ReentrancyGuardUpgradeable {
	address private cCA;
	CultureCoin private CC;

	Hero private hero;
	BaseSpells private spells;
	BaseLoot private loot;
	MyItems private items;

	mapping(address => bool) public isAddon;
	address[LEGION_LEGOS] private legionLegos;

	uint256 private heat;

	mapping(uint256 => int) private cubeBias;
	mapping(uint256 => int) private cubeWeight;

	mapping(uint256 => mapping(int => uint256)) private cubeSlots;

	int256 deltaMin;
	uint256 maxSearchDepth;
	uint256 cubeStartTime;

	mapping(uint256 => HeroXYZ) private heroHome;

	mapping(uint256 => HeroXYZ) private startXYZ;
	mapping(uint256 => uint256) private startPoint;
	mapping(uint256 => uint256) private startTime;

	uint256 private currentNodeId;
	uint256 private currentPairId;
	mapping(uint256 => KNODEPoint) private points;
	mapping(uint256 => KEDGEPair) private pairs;

	mapping(int => mapping(int => mapping(int => uint256))) knownPoints;
	mapping(uint256 => mapping(uint256 => uint256)) private knownPairs;

	struct KNODEPoint {
		uint256 id;
		int hX;
		int hY;
		int hZ;
		uint256[3] pointPairs;
	}
	struct KTri {
		uint256 one;
		uint256 two;
		uint256 three;
	}
	struct KEDGEPair {
		uint256 id;
		uint256 one;
		uint256 two;
	}
	function initialize (address _cCA, address _cultureCoin, address _hero, address _spells, address _loot, address _items, string memory _uri) external initializer {
		//__ERC1155_init(_uri);
		//__ERC1155Burnable_init();
		__ReentrancyGuard_init();

		cCA = _cCA;
		CC = CultureCoin(_cultureCoin);

		hero = Hero(_hero);
		spells = BaseSpells(_spells);
		loot = BaseLoot(_loot);
		items = MyItems(_items);
		heat = 1365; // 10101010101b in decimal

		cubeStartTime = block.timestamp;

		maxSearchDepth = 4;
		deltaMin = 0.0000001 ether;	// You must be htis close to the mesh to move on it.
		_initMap();
	}
	function _initMap() internal {
		/// bottom triangle point 
		KNODEPoint memory _b = KNODEPoint(1,1 ether,1 ether,1 ether, [uint256(1),uint256(2),uint256(3)]);
		_b.id = 1;			// MAP SPAWN ID 1 is (1, 1, 1) and all it's pairs are the same triangle with ids 2 and 3.
		_b.hX = 1 ether;
		_b.hY = 1 ether;
		_b.hZ = 1 ether;
		_b.pointPairs[0] = 1;		// Pair id one links points 1 and 2
		_b.pointPairs[1] = 2;		// Pair id two links points 2 and 3
		_b.pointPairs[2] = 3;		// Pair id three links points 1 and 3		...  They still need to be made below.

		// right triangle point
		KNODEPoint memory _r = KNODEPoint(2,11 ether,1 ether,1 ether, [uint256(1),uint256(2),uint256(3)]);
		_r.id = 2;			// MAP SPAWN ID 2 is (11, 1, 1) and all it's pairs are the same triangle with ids 1 and 3.
		_r.hX = 11 ether;
		_r.hY = 1 ether;		// RIGHT OR BOTTOM HAND SIDE OF THE TRIANGLE.
		_r.hZ = 1 ether;
		_r.pointPairs[0] = 1;		// Pair id one links points 1 and 2
		_r.pointPairs[1] = 2;		// Pair id two links points 2 and 3
		_b.pointPairs[2] = 3;		// Pair id three links points 1 and 3		...  They still need to be made below.

		/// left triangle point
		KNODEPoint memory _l = KNODEPoint(3,1 ether,11 ether,1 ether, [uint256(1),uint256(2),uint256(3)]);
		_l.id = 3;			// MAP SPAWN ID 3 is (11, 1, 1) and all it's pairs are the same triangle with ids 1 and 3.
		_l.hX = 1 ether;
		_l.hY = 11 ether;		// LEFT SIDE WALL OF THE TRIANGLE.
		_l.hZ = 1 ether;
		_l.pointPairs[0] = 1;		// Pair id one links points 1 and 2
		_l.pointPairs[1] = 2;		// Pair id two links points 2 and 3
		_l.pointPairs[2] = 3;		// Pair id three links points 1 and 3		...  They still need to be made below.

		KEDGEPair memory _pair;		// This is where we save the pairs we pointed to...
		_pair = KEDGEPair(1, 1, 2);
		knownPairs[1][2] = 1;
		knownPairs[2][1] = 1;
		pairs[1] = _pair;

		_pair = KEDGEPair(2, 2, 3);
		knownPairs[2][3] = 2;
		knownPairs[3][2] = 2;
		pairs[2] = _pair;

		_pair = KEDGEPair(3, 3, 1);
		knownPairs[1][3] = 3;
		knownPairs[3][1] = 3;
		pairs[3] = _pair;

		
		knownPoints[_b.hX][_b.hY][_b.hZ] = _b.id;		// Now the points are real or atleast known.
		knownPoints[_r.hX][_r.hY][_r.hZ] = _r.id;
		knownPoints[_l.hX][_l.hY][_l.hZ] = _l.id;

		points[_b.id] = _b;
		points[_r.id] = _r;
		points[_l.id] = _l;
		currentNodeId = 4;
		currentPairId = 4;
	}
	function _getPairId(uint256 _one, uint256 _two) internal returns(uint256) {
		uint256 _pairId1 = knownPairs[_one][_two];
		if(_pairId1 == 0) {
			uint256 _pairId2 = knownPairs[_two][_one];
			if(_pairId2 == 0) {
				KEDGEPair memory _pair = _newPair(_one, _two);
				return _pair.id;
			} else {
				return _pairId2;
			}
		}
		return _pairId1;
	}
	function _newPair(uint256 _one, uint256 _two) internal returns(KEDGEPair memory) {
		KEDGEPair memory _pair = KEDGEPair(currentPairId, _one, _two);
		knownPairs[_one][_two] = currentPairId;
		knownPairs[_two][_one] = currentPairId;
		pairs[currentPairId] = _pair;

		currentPairId++;
		return _pair;
	}
	event NewPoint(KNODEPoint point);

    function _newPoint(KTri memory _tri, HeroXYZ memory _dest) internal {
		// KEDGEPair memory _pair;

		KNODEPoint memory _point = KNODEPoint(currentNodeId,_dest.hX,_dest.hY,_dest.hZ,
			[uint256(_getPairId(_tri.one, _tri.two)),uint256(_getPairId(_tri.two, _tri.three)),uint256(_getPairId(_tri.three, _tri.one))]);
		_point.id = currentNodeId;
		_point.hX = _dest.hX;
		_point.hY = _dest.hY;
		_point.hZ = _dest.hZ;
		currentNodeId++;

		_point.pointPairs[0] = _getPairId(_tri.one, _tri.two);
		_point.pointPairs[1] = _getPairId(_tri.two, _tri.three);
		_point.pointPairs[2] = _getPairId(_tri.three, _tri.one);

		knownPoints[_point.hX][_point.hY][_point.hZ] = currentNodeId;
		points[currentNodeId] = _point;

		emit NewPoint(_point);
	}
	function sign1 (int _x) internal returns(int) {
		if (_x < 0) {
			return -1;
		}
		return 1;
	}
	event Clamp(string reason, int256 x, int256 value);

	function clamp1 (int _x) internal returns(int) {
		if(_x > 1 ether) {
			emit Clamp("1 ether", _x, 1 ether);
			return 1 ether;
		} 
		if(_x <= 0) {
			emit Clamp("Zeroed", _x, 0);
			return 0;
		}
		emit Clamp("Same", _x, _x);
		return  _x;
	}

	function _min(int _a, int _b) internal returns(int) {
		if(_a > _b) {
			return _b;
		}
		return _a;
	}
	event TestTriangleDFuncTurboSquared(int[3] dest, int[3] one, int[3] two, int[3] three);
	event TriDist(int d);
	function _kTriDist(KTri memory _tri, HeroXYZ memory _dest) internal returns(int) {
		int[3] memory dest;
		int[3] memory one;
		int[3] memory two;
		int[3] memory three;

		dest[0] = _dest.hX;
		dest[1] = _dest.hY;
		dest[2] = _dest.hZ;

		one[0] = _point(_tri.one).hX;
		one[1] = _point(_tri.one).hY;
		one[2] = _point(_tri.one).hZ;

		two[0] = _point(_tri.two).hX;
		two[1] = _point(_tri.two).hY;
		two[2] = _point(_tri.two).hZ;

		three[0] = _point(_tri.three).hX;
		three[1] = _point(_tri.three).hY;
		three[2] = _point(_tri.three).hZ;
		
		emit TestTriangleDFuncTurboSquared(dest, one, two, three);
		int distFromTri = triangleDFuncTurboSquared(dest, one, two, three);

		emit TriDist(distFromTri);
		return distFromTri;
	}
	event VA(int a, int b);
	event AfterDevision(int notzero);
	function triangleDFuncTurboSquared(int[3] memory _p, int[3] memory _a, int[3] memory _b, int[3] memory _c) public returns(int) {
    		int[36] memory _va;

    		_va[0]=_b[0]-_a[0]; _va[1]=_b[1]-_a[1]; _va[2]= _b[2]-_a[2];
    		_va[3]=_p[0]-_a[0]; _va[4]=_p[1]-_a[1]; _va[5]= _p[2]-_a[2];
    		_va[6]=_c[0]-_b[0]; _va[7]=_c[1]-_b[1]; _va[8]= _c[2]-_b[2];
    		_va[9]=_p[0]-_b[0]; _va[10]=_p[1]-_b[1]; _va[11]= _p[2]-_b[2];
    		_va[12]=_a[0]-_c[0]; _va[13]=_a[1]-_c[1]; _va[14]= _a[2]-_c[2];
    		_va[15]=_p[0]-_c[0]; _va[16]=_p[1]-_c[1]; _va[17]= _p[2]-_c[2];

    		_va[18] = _va[1] * _va[14] - _va[2] * _va[13];
    		_va[19] = _va[2] * _va[12] - _va[0] * _va[14];
    		_va[20] = _va[0] * _va[13] - _va[1] * _va[12];

    		_va[30] = (_va[1] * _va[20] - _va[2] * _va[19])*_va[3] + (_va[2] * _va[18] - _va[0] * _va[20])*_va[4] + (_va[0] * _va[19] - _va[1] * _va[18])*_va[5];
    		_va[31] = (_va[7] * _va[20] - _va[8] * _va[19])*_va[9] + (_va[8] * _va[18] - _va[6] * _va[20])*_va[10] + (_va[6] * _va[19] - _va[7] * _va[18])*_va[11];
    		_va[32] = (_va[13] * _va[20] - _va[14] * _va[19])*_va[15] + (_va[14] * _va[18] - _va[12] * _va[20])*_va[16] + (_va[12] * _va[19] - _va[13] * _va[18])*_va[17];

		//emit VA(_va[0]*_va[3]+_va[1]*_va[4]+_va[2]*_va[5], _va[0]*_va[0]+_va[1]*_va[1]+_va[2]*_va[2]);
		//emit VA(_va[6]*_va[9]+_va[7]*_va[10]+_va[8]*_va[11], _va[6]*_va[6]+_va[7]*_va[7]+_va[8]*_va[8]);
		//emit VA(_va[12]*_va[15]+_va[13]*_va[16]+_va[14]*_va[17], _va[12]*_va[12]+_va[13]*_va[13]+_va[14]*_va[14]);

		//emit AfterDevision(

    		if(sign1(_va[30])+sign1(_va[31])+sign1(_va[32])<2.0 ether){
			int a;
			int b;

			a = (_va[0]*_va[3]+_va[1]*_va[4]+_va[2]*_va[5]) * 1 ether * 1 ether;
			b = (_va[0]*_va[0]+_va[1]*_va[1]+_va[2]*_va[2]);
			if(a == 0 || b == 0) {
        			_va[33] = 0;
			} else {
        			_va[33]= clamp1(a/b);
			}

			a = (_va[6]*_va[9]+_va[7]*_va[10]+_va[8]*_va[11]) * 1 ether * 1 ether;
			b = (_va[6]*_va[6]+_va[7]*_va[7]+_va[8]*_va[8]);
			if(a == 0 || b == 0) {
                                _va[34] = 0;
                        } else {
                                _va[34]= clamp1(a/b);
                        }


			a = (_va[12]*_va[15]+_va[13]*_va[16]+_va[14]*_va[17]) * 1 ether * 1 ether;
			b = (_va[12]*_va[12]+_va[13]*_va[13]+_va[14]*_va[14]);
			if(a == 0 || b == 0) {
                                _va[35] = 0;
                        } else {
                                _va[35]= clamp1(a/b);
                        }

			//return 1;

        		_va[21]=_va[0]*_va[33]-_va[3]; _va[22]= _va[1]*_va[33]-_va[4];_va[23]= _va[2]*_va[33]-_va[5];
        		_va[24]=_va[6]*_va[34]-_va[9]; _va[25]= _va[7]*_va[34]-_va[10];_va[26]= _va[8]*_va[34]-_va[11];
        		_va[27]=_va[12]*_va[35]-_va[15]; _va[28]= _va[13]*_va[35]-_va[16];_va[29]= _va[14]*_va[35]-_va[17];
        		return (_min(_min(_va[21]*_va[21]+_va[22]*_va[22]+_va[23]*_va[23], _va[24]*_va[24]+_va[25]*_va[25]+_va[26]*_va[26]),  _va[27]*_va[27]+_va[28]*_va[28]+_va[29]*_va[29]));
    		}else{
        		_va[27] = _va[18]*_va[3] + _va[19]*_va[4] + _va[20]*_va[5]; //re-using 27 // JRR :::: https://npm.runkit.com/triangle-distance/index.js?t=1648422241177
        		return (_va[27]*_va[27]/(_va[18]*_va[18]+_va[19]*_va[19]+_va[20]*_va[20])); 
    		}
	}
	function _isXYZZeroZeroZero(HeroXYZ memory _xyz) internal returns (bool) {
		return _xyz.hX == 0 && _xyz.hY == 0 && _xyz.hZ == 0;
	}
	function _point(uint256 _pId) internal returns(KNODEPoint memory) {
		return points[_pId];
	}
	event PointFromXYZ(HeroXYZ XYZ, uint256 pointId);
	function _pointFromXYZ(HeroXYZ memory _curXYZ) internal returns(uint256) {
		//return points[knownPoints[_curXYZ.hX][_curXYZ.hY][_curXYZ.hZ]];
		emit PointFromXYZ(_curXYZ, knownPoints[_curXYZ.hX][_curXYZ.hY][_curXYZ.hZ]);
		if(knownPoints[_curXYZ.hX][_curXYZ.hY][_curXYZ.hZ] != 0) {
			return knownPoints[_curXYZ.hX][_curXYZ.hY][_curXYZ.hZ];
		}
		return 1;
	}
	function _getHeroHomeXYZ(uint256 _hId) internal returns(HeroXYZ memory) {
		return heroHome[_hId];
	}
	event Point(address hero, uint256 hId, uint256 pId);
	event Node(uint256 id);
	function walkStart(uint256 _hId) public {
		require(msg.sender == hero.ownerOf(_hId) || cCA == msg.sender || isAddon[msg.sender], "You don't own that hero.");
		HeroXYZ memory _curXYZ = spells.getXYZ(address(hero), _hId);
		if(_isXYZZeroZeroZero(_curXYZ)) {
			_curXYZ = _getHeroHomeXYZ(_hId);
			if(_isXYZZeroZeroZero(_curXYZ)) {
				_curXYZ = HeroXYZ(1 ether, 1 ether, 1 ether, 0, 0);		// 1 x, 1 y, and 1 z. :: on the ground at the start of the map. Z = 0 is generally lava...
			}
		}
		emit Point(address(hero), _hId, _pointFromXYZ(_curXYZ));
		startPoint[_hId] = _pointFromXYZ(_curXYZ);

		KNODEPoint memory _startPoint = _point(startPoint[_hId]);

		emit Node(_startPoint.id);
		startTime[_hId] = block.timestamp;

		require(_startPoint.id != 0, "Not this bug again.");
		if(_startPoint.id == 0) {
			//_startPoint.id = 1;
			emit XYZ(address(hero), _hId, _curXYZ.hX, _curXYZ.hY, _curXYZ.hZ);
		}

		heat++;
	}
	event WalkEnd(uint256 pId);
	function walkEnd(uint256 _hId, int _x, int _y, int _z) public {
		require(startTime[_hId] >= cubeStartTime, "No one may end a translocation, without starting one first. Not even the admins may do that.");
		require(msg.sender == hero.ownerOf(_hId) || cCA == msg.sender || isAddon[msg.sender], "You don't own that hero.");
		HeroXYZ memory _dest = HeroXYZ(_x,_y,_z, 0,0);
		uint dist = spells.xyzDist(_startXYZ(_hId), _dest);
		if(dist > 30.0 ether) {
			//emit Debug1(30);
			dist = 30.0 ether;
		}
		if (dist <= 1.0 ether * (block.timestamp - startTime[_hId])) {
			//emit Debug1(dist);
			HeroXYZ memory loc = _getRealLocationXYZ(_startXYZ(_hId), _dest);
			spells.setXYZ(address(hero), _hId, loc.hX, loc.hY, loc.hZ);
			startPoint[_hId] = _pointFromXYZ(loc);
			startTime[_hId] = block.timestamp;
			emit WalkEnd(startPoint[_hId]);
		} 
	}
	function _doesPathExists(KNODEPoint memory _startPoint, HeroXYZ memory _dest, uint _depth) internal returns(bool) {// This code is pretty terrible. Probably only want to recurse like 2-3 times.
                KEDGEPair memory pair;
                for(uint j = 0; j < 3; j++) {
                	uint256 _pair = _startPoint.pointPairs[j];
                	pair = pairs[_pair];
                        KTri memory _tri = KTri(pair.one, pair.two, _startPoint.id);

                        int distFromTriangle = _kTriDist(_tri, _dest);
                        if(distFromTriangle < deltaMin) {
                        	_newPoint(_tri, _dest);
				return true;
                        }
                }
		if(_depth > maxSearchDepth) {
			return false;
		}
		for(uint j = 0; j < 3; j++) {
                	uint256 _pair = _startPoint.pointPairs[j];
                	pair = pairs[_pair];
			if(_doesPathExists(_point(pair.one), _dest, _depth+1)) {
				return true;
			}
			if(_doesPathExists(_point(pair.two), _dest, _depth+1)) {
				return true;
			}
		}
		return false;
	}
	// You can get 1.0 ether steps per second for walking. Running and moving faster than the speed
	// of light is possible.
	function _goTo(KNODEPoint memory _startPoint, HeroXYZ memory _dest, uint256 _steps, uint _speed) internal returns(HeroXYZ memory) {
		HeroXYZ memory testLoc = _dest;	// do the whole thing, because this movement is on the mesh.

		bool pathExists = _doesPathExists(_startPoint, testLoc, 0);
		if(pathExists) {
			return _dest;
		}
		return HeroXYZ(_startPoint.hX, _startPoint.hY, _startPoint.hZ, 0, 0);
/*
		HeroXYZ _unitVec = _getUnitVector(_startPoint, _dest);
		HeroXYZ curLoc = HeroXYZ(_startPoint.hX, _startPoint.hY, _startPoint.hZ, 0, 0);
		for(uint i = 1; i <= _steps / _speed; i++) {	// And we calculate time using 1 second increments.	
			testLoc = _addXYZ(curLoc, _unitVec);

			bool pathExists = _doesPathExists(_startPoint, testLoc);
			if(!pathExists) {
				break;
			}
		}
		return curLoc;
*/
	}
	function _getRealLocationXYZ(HeroXYZ memory _start, HeroXYZ memory _dest) internal returns(HeroXYZ memory) {
		KNODEPoint memory _startPoint = _point(_pointFromXYZ(_start));
		if(!_pointKnown(_startPoint)) {
			emit Debug1(10000);
			return HeroXYZ(0,0,0, 0,0);
		}
		return _goTo(_startPoint, _dest, 1.0 ether, 1.0 ether);
	}
	event Debug1(uint happened);
	event XYZ(address hero, uint256 hId, int x, int y, int z);
	function _startXYZ(uint256 _hId) internal returns(HeroXYZ memory) {
		KNODEPoint memory _point = points[startPoint[_hId]];
		return HeroXYZ(_point.hX, _point.hY, _point.hZ, 0,0);
	}
	function _pointKnown(KNODEPoint memory _point) internal returns(bool) {
		if(_point.id != 0) {
			return true;
		}
		return false;
	}
	function cubeTime() public returns(uint256) {
		heat++;
		return block.timestamp;
	}
	function timeCube(uint256 _hId, uint _times) public {
		require(msg.sender == hero.ownerOf(_hId) || cCA == msg.sender || isAddon[msg.sender], "You don't own that hero.");
		spells.castTo(address(hero), _hId, CUBE_TIME, 1);		// This keeps track of the actual times this function is called by the hero.
		//_mint(msg.sender, _hId, cubeTime() * _times, "");
		heat++;
	}
	function hitCube(uint256 _hId, uint _times) public {
		require(msg.sender == hero.ownerOf(_hId) || cCA == msg.sender || isAddon[msg.sender], "You don't own that hero.");
		spells.castTo(address(hero), _hId, CUBE_DUST, 9);
		loot.lootTo(address(hero), _hId, _hId, 1);
		//_mint(msg.sender, _hId, cubeTime() / _times, "");
		heat++;
	}
	event Dice(HeroItem item);
	event Transmute(uint256 newItem, int slot, uint w1, uint a1, uint w2, uint a2, uint w3, uint a3, uint w4, uint a4);
	event Summoned(uint256 hId, uint256 whatId);            // WhatId is a summoned hero's id.
        function summon(uint256 _hId, uint256 _whatId) public {
                require(isAddon[msg.sender] || msg.sender == cCA);
                emit Summoned(_hId, _whatId);
        }
        event Unsummoned(uint256 hId, uint256 whatId);
        function unsummon(uint256 _hId, uint256 _whatId) public {
                require(isAddon[msg.sender] || msg.sender == cCA);
                emit Unsummoned(_hId, _whatId);
        }

	function diceTheItem(HeroItem memory _item, uint256 _entropy, uint _power, uint _gasReward) internal returns(HeroItem memory) {
		uint powerMult = spells.log2(_power) + 1;

		_item.level = powerMult;
		_item.stam = int(powerMult);

		_item.intel += int((_entropy % 10) * powerMult);
		_entropy = uint(keccak256(abi.encodePacked(_entropy+1)));
		_item.strn += int((_entropy % 10) * powerMult);
		_entropy = uint(keccak256(abi.encodePacked(_entropy+1)));
		_item.agi += int((_entropy % 10) * powerMult);
		_entropy = uint(keccak256(abi.encodePacked(_entropy+1)));

		_item.armor += int((_entropy % 40) * powerMult);
		_entropy = uint(keccak256(abi.encodePacked(_entropy+1)));

		_item.fire += int((_entropy % 4) * powerMult);
		_entropy = uint(keccak256(abi.encodePacked(_entropy+1)));
		_item.frost += int((_entropy % 4) * powerMult);
		_entropy = uint(keccak256(abi.encodePacked(_entropy+1)));
		_item.meta += int((_entropy % 3) * powerMult);
		_entropy = uint(keccak256(abi.encodePacked(_entropy+1)));

		_entropy = (_entropy << (256 - 8));		// Do this last. destructive...
		_entropy = (_entropy >> (256 - 8));

		_item.effect = (1 << _entropy);

		emit Dice(_item);
		return _item;
	}
	function equipItem(uint256 _hId, uint256 _iId) public {
                require(hero.ownerOf(_hId) == msg.sender || msg.sender == cCA, "equipItem");
		items.equipItemFrom(msg.sender, address(hero), _hId, _iId);
	}
	function cubeItem(uint256 _hId, uint256 _iId, int _cubeSlot) public {
		require(Hero(hero).ownerOf(_hId) == msg.sender || msg.sender == cCA || isAddon[msg.sender], "setItem");

		require(1 <= _cubeSlot && _cubeSlot <= int(MAX_CUBE_SLOTS), "_cubeSlot");

                if(_iId > 0) {
			items.addonApprove(address(this), msg.sender, _iId);
                        items.safeTransferFrom(msg.sender, address(this), _iId);
                }

                uint256 _curItemId = cubeSlots[_hId][_cubeSlot];
                if(_curItemId > 0) {
                        items.safeTransferFrom(address(this), msg.sender, _curItemId);
                }
                cubeSlots[_hId][_cubeSlot] = _iId;
	}
	function cubeEffect(uint256 _hId) public returns(uint256) {
		uint256 effect;
		for(int i = 1; i <= MAX_CUBE_SLOTS; i++) {
			uint256 itemId = cubeSlots[_hId][i];
			HeroItem memory item = items.getItemStats(itemId);
			effect |= item.effect;
		}
		return effect;
	}
	function setCubeBias(uint256 _hId, int _bias) public {
		require(cCA == msg.sender || isAddon[msg.sender], "You don't own that, b.");
		cubeBias[_hId] = _bias;
	}
	function setCubeWeight(uint256 _hId, int _weight) public {
		require(cCA == msg.sender || isAddon[msg.sender], "You don't own that, w.");
		cubeWeight[_hId] = _weight;
	}
	function transmuteCube(uint256 _hId, int _slot) public {	// Blow up all the items for a master item or junk.
		require(msg.sender == hero.ownerOf(_hId) || cCA == msg.sender || isAddon[msg.sender], "You don't own that hero.");
		uint256 effect = cubeEffect(_hId);

		uint _totalLvl;
		for(int i = 1; i <= MAX_CUBE_SLOTS; i++) {
                        uint256 itemId = cubeSlots[_hId][i];
			HeroItem memory item = items.getItemStats(itemId);
			_totalLvl += item.level;
                        items.burn(itemId);
                }

		uint256 newItem = items.itemMint(address(hero), _hId, address(this), _slot);
		HeroItem memory item = items.getItemStats(newItem);
		item.slot = _slot;
		(uint256 gasReward, ) = BookTradable(hero.getNBT()).getGasRewards(hero.getSpawn(_hId));
                diceTheItem(item, uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, heat, effect))), _totalLvl / (uint(MAX_CUBE_SLOTS) + 1), gasReward);
		item.effect |= effect;
                items.setItemStats(newItem, item);

		cubeSlots[_hId][_slot] = newItem;
	}
	function transmute(uint256 _hId, int _slot, uint _time, uint _what, uint _amount) public returns(uint256) {
		require(msg.sender == hero.ownerOf(_hId) || cCA == msg.sender || isAddon[msg.sender], "You don't own that hero.");
		loot.burnFrom(msg.sender, _what, _amount);
		
		(uint256 gasReward, ) = BookTradable(hero.getNBT()).getGasRewards(hero.getSpawn(_hId));
		
		uint256 newItem = items.itemMint(address(hero), _hId, msg.sender, _slot);

		HeroItem memory item = items.getItemStats(newItem);
		item.slot = _slot;
		diceTheItem(item, uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, heat, _what, _amount))), _amount, gasReward);
		items.setItemStats(newItem, item);

		emit Transmute(newItem, _slot, _what, _amount, 0, 0,  0, 0,  0, 0);
		return newItem;
	}
	function transmute(uint256 _hId, int _slot, uint _time, uint _what, uint _amount, uint _w2, uint _a2) public {
                require(msg.sender == hero.ownerOf(_hId) || cCA == msg.sender || isAddon[msg.sender], "You don't own that hero.");
		//_burn(msg.sender, _hId, _time);
		(uint256 gasReward, ) = BookTradable(hero.getNBT()).getGasRewards(hero.getSpawn(_hId));
		loot.burnFrom(msg.sender, _what, _amount);
		loot.burnFrom(msg.sender, _w2, _a2);

		uint256 newItem = items.itemMint(address(hero), _hId, msg.sender, _slot);

		HeroItem memory item = items.getItemStats(newItem);
		item.slot = _slot;
		item = diceTheItem(item, uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, heat, _what, _amount, _w2, _a2))), _amount + _a2, gasReward);
		items.setItemStats(newItem, item);

		emit Transmute(newItem, _slot, _what, _amount, _w2, _a2,  0, 0,  0, 0);
	}
	function castAO(uint256 _hId, uint256 _to1, uint256 _to2) public returns (int256) {
		require(hero.ownerOf(_hId) == msg.sender || isAddon[msg.sender], "You can't do that.");
		spells.castAO(address(hero), _hId, _to1, _to2);
		Stats memory stats = items.getStats(address(hero), _hId);
		stats.effect |= cubeEffect(_hId);
		playLegend(LEGO_CAST, ARCANE_ORB, stats, _hId, _to1, _to2);
		return ARCANE_ORB;
	}
	function activateAO(uint256 _hId, uint256 _target, int _how, uint _amount) public returns (uint256) {
		require(hero.ownerOf(_hId) == msg.sender || isAddon[msg.sender], "You can't do that.");
		Stats memory stats = loot.activateAO(address(hero), _hId, _target, _how, _amount);
		stats.effect |= cubeEffect(_hId);
		playLegend(LEGO_ACTIVATE, ARCANE_ORB, stats, _hId, _target, _how, _amount);
		return stats.effect;
	}
	function castRES(uint256 _hId, uint256 _target) public returns(uint) {
		require(hero.ownerOf(_hId) == msg.sender || isAddon[msg.sender], "You can't do that.");
		uint hp = loot.castRES(address(hero), _hId, _target);
		Stats memory stats = items.getStats(address(hero), _hId);
		stats.effect |= cubeEffect(_hId);
		playLegend(LEGO_CAST, RESURECTION, stats, _hId, _target);
		return hp;
	}
	function castIS(uint256 _hId) public returns(uint) {
		require(hero.ownerOf(_hId) == msg.sender || isAddon[msg.sender], "You can't do that.");

		loot.castIS(address(hero), _hId);
		Stats memory stats = items.getStats(address(hero), _hId);
		stats.effect |= cubeEffect(_hId);
		playLegend(LEGO_CAST, IRON_SKIN, stats, _hId);
	}
	function playLegend(uint _playHow, int _spell, Stats memory _stats, uint256  _hId) internal {
		for(uint i = 0; i < LEGION_LEGOS; i++) {
			address legion = legionLegos[i];
			if(legion != address(0)) {
				Legion(legion).playLegend(_playHow, ARCANE_ORB, _stats, _hId);
			}
		}
		if(_playHow == LEGO_CAST) {
			if(hero.canCast(_hId, IRON_SKIN) && _stats.effect & L_IRON_SKIN_HEALS > 0) {
				//uint256 _hId, uint256 _target, uint _amount, int _healType, uint _effect
				hero.healByPercent(_hId, _hId, 0.20 ether, IRON_SKIN, L_IRON_SKIN_HEALS);
			}
		}
	}
	function playLegend(uint _playHow, int _spell, Stats memory _stats, uint256 _hId, uint256 _to1, uint256 _to2) internal {

	}
	function playLegend(uint _playHow, int _spell, Stats memory _stats, uint256 _hId, uint256 _target) internal {
		
	}
	function playLegend(uint _playHow, int _spell, Stats memory _stats, uint256 _hId, uint256 _target, int _how, uint256 _amount) internal {
		for(uint i = 0; i < LEGION_LEGOS; i++) {
			address legion = legionLegos[i];
			if(legion != address(0)) {
				Legion(legion).playLegend(_playHow, ARCANE_ORB, _stats, _hId, _target, _how, _amount);
			}
		}
	}
	function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4) {
		return 0xf0b9e5ba;
	}

	function setLegionAddrs(address[] memory _addrs) public {
		require(msg.sender == cCA || isAddon[msg.sender], "setItem");
		for (uint i = 0; i < LEGION_LEGOS; i++) {
			legionLegos[i] = _addrs[i];
		}
	}
}