// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/* Официальная библиотека Zama */
import {FHE, ebool, euint32, externalEuint32} from "@fhevm/solidity/lib/FHE.sol";
/* Конфиг Sepolia — контракт знает адреса протокольных сервисов Zama */
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

/**
 * @title ChildPlaytimeLimiter
 * @notice Личный лимитер «игровых часов» для ребёнка.
 *
 * Модель:
 *  - Родитель и Ребёнок независимо загружают свои недельные правила:
 *    для каждого дня недели хранится euint32-маска, где 24 младших бита соответствуют часам 0..23 (UTC).
 *    Бит=1 означает «час разрешён».
 *  - Контракт при запросе вычисляет ebool = (parentMask[day] & childMask[day]) содержит бит текущего часа.
 *  - Публично раскрывается ТОЛЬКО итоговый флаг «можно/нельзя сейчас» (через makePubliclyDecryptable).
 *  - Конкретные маски/цифры остаются приватными.
 *
 * Замечания по FHE:
 *  - FHE-операции выполняются только в nonpayable функциях (не view/pure).
 *  - Используются только поддерживаемые операции: and, gt, select, сравнения и приведения.
 */
contract ChildPlaytimeLimiter is SepoliaConfig {
    /* ───────────────────── Ownable ───────────────────── */

    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero owner");
        owner = newOwner;
    }

    /* ───────────────────── Роли ───────────────────── */

    address public parent;
    address public child;

    modifier onlyParent() {
        require(msg.sender == parent, "Only parent");
        _;
    }
    modifier onlyChild() {
        require(msg.sender == child, "Only child");
        _;
    }

    event RolesSet(address indexed parent, address indexed child);

    /// @notice Установить адреса родителя и ребёнка (только владелец).
    function setRoles(address _parent, address _child) external onlyOwner {
        require(_parent != address(0) && _child != address(0), "Zero role");
        parent = _parent;
        child = _child;
        emit RolesSet(_parent, _child);
    }

    /* ───────────────────── Хранилище правил ─────────────────────
       Для каждого дня недели (0=Mon .. 6=Sun) храним euint32 маску:
       24 младших бит → часы 0..23 (UTC). 1 = разрешён.
    */

    mapping(uint8 => euint32) private _parentMask;
    mapping(uint8 => euint32) private _childMask;

    event ParentRuleUpdated(uint8 indexed day, bytes32 handle);
    event ChildRuleUpdated(uint8 indexed day, bytes32 handle);
    event Cleared(address indexed by, uint8 indexed day);

    /// @notice Версия контракта для фронта/диагностики.
    function version() external pure returns (string memory) {
        return "ChildPlaytimeLimiter/1.0.2-sepolia";
    }

    /* ───────────────────── Загрузка правил ───────────────────── */

    /// @notice Родитель загружает маску на день (euint32) как external ciphertext.
    function parentSetDayMask(uint8 day, externalEuint32 maskExt, bytes calldata proof) external onlyParent {
        require(day < 7, "day 0..6");
        euint32 m = FHE.fromExternal(maskExt, proof); // проверка аттестации внутри
        FHE.allowThis(m); // контракт сможет переиспользовать шифртекст
        _parentMask[day] = m;
        emit ParentRuleUpdated(day, FHE.toBytes32(m));
    }

    /// @notice Ребёнок загружает маску на день (euint32) как external ciphertext.
    function childSetDayMask(uint8 day, externalEuint32 maskExt, bytes calldata proof) external onlyChild {
        require(day < 7, "day 0..6");
        euint32 m = FHE.fromExternal(maskExt, proof);
        FHE.allowThis(m);
        _childMask[day] = m;
        emit ChildRuleUpdated(day, FHE.toBytes32(m));
    }

    /// @notice Очистить маску дня (разрешено родителю или ребёнку для своей стороны).
    function clearDay(uint8 day) external {
        require(day < 7, "day 0..6");
        euint32 z = FHE.asEuint32(0);
        FHE.allowThis(z);

        if (msg.sender == parent) {
            _parentMask[day] = z;
            emit Cleared(msg.sender, day);
        } else if (msg.sender == child) {
            _childMask[day] = z;
            emit Cleared(msg.sender, day);
        } else {
            revert("Only parent/child");
        }
    }

    /* ───────────────────── Вспомогательные (plaintext) ───────────────────── */

    /// @dev День недели UTC: 0=Mon .. 6=Sun
    function _dayOfWeek(uint256 ts) internal pure returns (uint8) {
        return uint8(((ts / 86400) + 4) % 7);
    }

    /// @dev Час суток UTC: 0..23
    function _hourOfDay(uint256 ts) internal pure returns (uint8) {
        return uint8((ts / 3600) % 24);
    }

    /* ───────────────────── События результатов ───────────────────── */

    /// @notice Пишем хэндл итогового флага (ebool) — дешифруется публично через relayer.publicDecrypt(handle).
    event PolicyChecked(address indexed who, uint8 day, uint8 hour, bytes32 allowedHandle);

    /* ───────────────────── Основные проверки ───────────────────── */

    /// @notice «Можно ли играть сейчас?» (UTC). Возвращает ebool (как bytes32-хэндл) + эмитит PolicyChecked.
    /// @dev nonpayable: внутри вызываются FHE-операции и makePubliclyDecryptable.
    function canPlayNow() external returns (ebool allowedCt) {
        uint8 day = _dayOfWeek(block.timestamp);
        uint8 hour = _hourOfDay(block.timestamp);

        euint32 pm = _parentMask[day];
        euint32 cm = _childMask[day];

        // Бит текущего часа: 1 << hour
        uint32 bit = (uint32(1) << uint32(hour));

        // Разрешено, если и у родителя, и у ребёнка в этом часу стоит 1
        ebool pOK = FHE.gt(FHE.and(pm, FHE.asEuint32(bit)), FHE.asEuint32(0));
        ebool cOK = FHE.gt(FHE.and(cm, FHE.asEuint32(bit)), FHE.asEuint32(0));
        ebool allowed = FHE.and(pOK, cOK);

        // Публичная дешифровка только итогового флага
        FHE.makePubliclyDecryptable(allowed);

        // Отдадим хэндл в событии для фронта
        emit PolicyChecked(msg.sender, day, hour, FHE.toBytes32(allowed));

        return allowed;
    }

    /// @notice «Можно ли играть в конкретный момент ts (UTC)?» Удобно для тестов/превью.
    function canPlayAt(uint256 ts) external returns (ebool allowedCt) {
        uint8 day = _dayOfWeek(ts);
        uint8 hour = _hourOfDay(ts);

        euint32 pm = _parentMask[day];
        euint32 cm = _childMask[day];

        uint32 bit = (uint32(1) << uint32(hour));

        ebool pOK = FHE.gt(FHE.and(pm, FHE.asEuint32(bit)), FHE.asEuint32(0));
        ebool cOK = FHE.gt(FHE.and(cm, FHE.asEuint32(bit)), FHE.asEuint32(0));
        ebool allowed = FHE.and(pOK, cOK);

        FHE.makePubliclyDecryptable(allowed);

        emit PolicyChecked(msg.sender, day, hour, FHE.toBytes32(allowed));

        return allowed;
    }

    /* ───────────────────── Отладочные хэндлы (без раскрытия значений) ───────────────────── */

    /// @notice Вернуть bytes32-хэндлы масок на день (для диагностики/аудита фронтом).
    function getDayHandles(uint8 day) external view returns (bytes32 parentMaskH, bytes32 childMaskH) {
        require(day < 7, "day 0..6");
        return (FHE.toBytes32(_parentMask[day]), FHE.toBytes32(_childMask[day]));
    }
}
