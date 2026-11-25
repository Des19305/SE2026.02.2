# Nhóm A — Shared Contract cần cập nhật cho Issue #5

## 1. Equipment API & Signal

### 1.1. Equipment API

Equipment Manager cung cấp các API:

- `equip_item(item_id: String, slot: String) -> Dictionary`
- `unequip_item(slot: String) -> Dictionary`
- `get_equipment() -> Dictionary`

Player owns the authoritative Combat state and provides:

- `start_combat()`
- `end_combat()`
- `is_in_combat() -> bool`
- `combat_state_changed(is_in_combat: bool)`

Future Combat gameplay must call `start_combat()` and `end_combat()` explicitly.
Phase 7 does not implement Enemy, encounter detection, timers, or automatic Combat transitions.

Equipment Manager chịu trách nhiệm quản lý equipment state và đảm bảo các thao tác equip, unequip, replace được thực hiện an toàn.

While `Player.is_in_combat()` is true, `equip_item()` and `unequip_item()` must return `{"ok": false, "error": "in_combat"}` before changing Equipment, Inventory, or Player effects. This restriction covers Equipment, Accessories, replacements, empty slots, dynamic slots, and same-item equip calls.

Chi tiết cấu trúc dữ liệu trả về của `get_equipment()` chưa chốt, không tự ý định nghĩa trong giai đoạn cập nhật contract.

### 1.2. Equipment Signals

Equipment Manager cung cấp các signal:

```gdscript
signal equipment_changed
signal equipment_slots_changed
```

**`equipment_changed`**
- Emit khi equipment state thực sự thay đổi sau thao tác equip, unequip hoặc replace thành công.
- Không emit khi thao tác thất bại hoặc không làm thay đổi trạng thái equipment.
- Signal không có payload. Module nhận signal có thể gọi `get_equipment()` để lấy state mới nhất.

**`equipment_slots_changed`**
- Emit khi danh sách equipment slots thay đổi, chẳng hạn khi Player được mở thêm slot.
- Không emit khi thao tác mở slot thất bại hoặc không làm thay đổi danh sách slot.
- Signal không có payload.

Nếu một thao tác làm thay đổi cả equipment state và slot list, có thể emit cả hai signal sau khi state đã được cập nhật hoàn toàn.

---

## 2. Minimum Equipment Metadata

### 2.1. Item Type và Tags

Item Definition cần phân biệt:

- `item_type`: loại chính của item, ví dụ `equipment`, `consumable`, `quest`, `material`.
- `tags`: danh sách tag linh hoạt phục vụ filter, sort, tìm kiếm và phân loại item trong Inventory.

`item_type` và `tags` là hai khái niệm riêng biệt. Tags không thay thế các metadata cần thiết cho logic Equipment.

Các loại item và tags có thể được mở rộng trong tương lai.

### 2.2. Equipment Slot Compatibility

Equipment metadata sử dụng:

- `allowed_slot_types`: danh sách các loại slot mà item có thể được trang bị.
- `slots_required`: số lượng equipment slots cần chiếm.

Ví dụ:

**Sword**

```json
{
  "allowed_slot_types": ["weapon"],
  "slots_required": 1
}
```

**Bow**

```json
{
  "allowed_slot_types": ["weapon"],
  "slots_required": 2
}
```

**Helmet**

```json
{
  "allowed_slot_types": ["helmet"],
  "slots_required": 1
}
```

Không sử dụng `is_two_handed`. Số slot mà item cần chiếm được xác định bằng `slots_required`.

Equipment Manager chịu trách nhiệm xác định các slot cần chiếm, kiểm tra tính hợp lệ và quản lý các slot bị reserved.

### 2.3. Equipment Slots

Equipment Manager sở hữu và quản lý toàn bộ Equipment Slots của Player.

- Player bắt đầu với 7 equipment slots mặc định.
- Số lượng slots không bị giới hạn cố định ở 7 trong suốt quá trình chơi.
- Có thể thêm slot trong run thông qua gameplay effects, buffs, items hoặc các cơ chế mở rộng trong tương lai.
- Mỗi slot có `slot_id` duy nhất và `slot_type`.
- Slot mới được thêm phải ở trạng thái available, chưa chứa item.
- Việc thêm slot không được làm mất hoặc thay đổi equipment hiện có.
- MVP chỉ hỗ trợ thêm slot; chưa hỗ trợ xóa slot.

Equipment Manager phải quản lý slot availability và reservation. Một slot bị reserved bởi equipment khác không thể được sử dụng để equip item mới.

Ví dụ: Bow cần 2 weapon slots. Khi được equip vào một weapon slot, slot weapon còn lại được reserved. Khi Bow được unequip hoặc thay thế thành công bằng item khác, slot được giải phóng và trở lại trạng thái available nếu không còn bị chiếm dụng.

---

## 3. Equipment Validation

Equipment Manager chịu trách nhiệm validate các thao tác equip, unequip và replace dựa trên Item Database metadata và Equipment state.

Các validation tối thiểu bao gồm:

- Item tồn tại trong Item Database.
- Item có thể equip (`item_type` phù hợp).
- Slot tồn tại và đã được mở/unlocked.
- Slot type tương thích với `allowed_slot_types`.
- Các slot cần chiếm theo `slots_required` có thể được sử dụng hợp lệ.
- Không xung đột với equipment đang được trang bị hoặc reserved.
- Inventory và Equipment có thể hoàn thành transfer an toàn.

Item Database chỉ cung cấp Item Definition và metadata; không tự quyết định hoặc thực hiện thao tác equip.

Equipment Manager chịu trách nhiệm validation và quyết định thao tác equip có hợp lệ hay không.

---

## 4. Atomic Equipment Operations & Inventory Integration

Equip, unequip và replace phải đảm bảo atomicity.

- Nếu thao tác thất bại, không được để Inventory hoặc Equipment ở trạng thái thay đổi một phần.
- Không làm mất item trong quá trình transfer giữa Inventory và Equipment.
- Khi replace equipment, item cũ phải được trả về Inventory thành công trước khi hoàn tất thay thế.
- Nếu không thể hoàn tất transfer hoặc replace an toàn, thao tác phải thất bại và state trước đó được giữ nguyên.
- Equipment Manager và Inventory Manager phải phối hợp qua shared API/contracts; không truy cập hoặc sửa trực tiếp state nội bộ của module còn lại trái với ownership.

---

## 5. Equipment Effects & Module Ownership

### 5.1. Effect Metadata

Item Definition có thể lưu danh sách `effects` mô tả passive/stat effects của equipment.

Format đề xuất:

```json
{
  "effects": [
    {
      "type": "stat_modifier",
      "stat": "defense",
      "operation": "add",
      "value": 5
    }
  ]
}
```

Các field cơ bản:

- `type`: loại effect.
- `stat`: stat chịu ảnh hưởng, khi áp dụng.
- `operation`: cách tính modifier, ví dụ `add`, `multiply`.
- `value`: giá trị effect.
- Các field bổ sung chỉ được sử dụng khi effect yêu cầu, ví dụ `hp_behavior` cho Max HP effects.

Item Database lưu metadata; không trực tiếp tính toán hoặc apply effect.

### 5.2. Ownership

- **Equipment Manager:** Quản lý equipment state, slot, compatibility, reservation, tổng hợp effects và điều phối việc cập nhật effects khi equipment thay đổi.
- **Item Database:** Cung cấp Item Definition, item type, tags, slot requirements và effects.
- **Inventory Manager:** Quản lý item count và phối hợp transfer item với Equipment Manager.
- **Player/Stat handling:** Long phụ trách; chịu trách nhiệm xử lý và áp dụng stat/effects lên Player thông qua interface được thống nhất.
- **Combat:** Sử dụng các stat/effect interface đã thống nhất; không mở rộng hoặc triển khai Combat trong phạm vi cập nhật Issue #5 shared contract.

### 5.3. Effect Integration Boundary

Equipment Manager không trực tiếp sửa các stat nội bộ của Player.

Khi equipment thay đổi, Equipment Manager điều phối việc cập nhật effects dựa trên equipment state mới. Player/Stat handling chịu trách nhiệm áp dụng stat changes.

Effects phải được đồng bộ chính xác theo equipment state hiện hành, tránh cộng chồng lặp hoặc không gỡ được effects khi unequip/replace.

Ưu tiên tính toán lại tổng effects từ toàn bộ equipment đang có hiệu lực để đảm bảo stat state chính xác sau các thao tác equip, unequip hoặc replace.

Interface cụ thể giữa Equipment Manager và Player/Stat handling sẽ được xác định khi đối chiếu Architecture hiện tại, tránh tạo API trùng hoặc xung đột.

---

## 6. Max HP Effects

Equipment effects có thể thay đổi Max HP theo hai behavior:

- `increase_max_only`: Tăng Max HP nhưng không thay đổi Current HP.
- `increase_max_and_current`: Tăng Max HP và Current HP bằng cùng lượng Max HP được tăng.

Ví dụ effect tăng `20 Max HP`:

| Behavior | Max HP thay đổi | Current HP thay đổi |
|---|---:|---:|
| `increase_max_only` | +20 | 0 |
| `increase_max_and_current` | +20 | +20 |

Khi Max HP giảm do equipment effect bị gỡ:

- Max HP giảm theo tổng effect mới.
- Current HP không được tự hồi.
- Current HP phải được clamp để không vượt Max HP mới.

### 6.1. Player HP Signals

Giữ nguyên contract hiện tại:

```gdscript
signal health_changed(current_hp: int, max_hp: int)
```

Signal `health_changed` chỉ emit khi Current HP thực sự thay đổi. Max HP thay đổi nhưng Current HP không đổi thì không emit signal này.

Bổ sung:

```gdscript
signal max_hp_changed(max_hp: int)
```

- Emit khi Max HP thực sự thay đổi.
- HUD sử dụng signal này để refresh Max HP.
- Khi Max HP và Current HP cùng thay đổi, có thể emit cả `max_hp_changed` và `health_changed`.
- Không emit nếu Max HP không thay đổi.

---

## 7. Scope Boundaries

Các contract trong tài liệu này chỉ xác định shared API, metadata, ownership, validation, state management và integration boundaries.

Không thuộc phạm vi cập nhật shared contract của Issue #5:

- Triển khai Shield blocking mechanics.
- Triển khai Bow charging/shooting.
- Triển khai Combat hoặc dual-wield mechanics.
- Công thức damage, stat scaling hoặc combat balance.
- Item catalog đầy đủ.
- Target-dependent Key/Quest item behavior.
- Concrete `get_equipment()` snapshot shape chưa được thống nhất.

Các behavior trên chỉ được triển khai khi có contract hoặc scope riêng được thống nhất.

---

## 8. Implementation/Testing Implications

Các contract này là cơ sở để cập nhật Architecture và Issue #5 design. Khi triển khai, cần đảm bảo:

- Equipment state và slot reservation luôn hợp lệ.
- Equip/unequip/replace atomic, không mất item.
- Item type, slot requirements và compatibility được validate từ metadata.
- Equipment effects được đồng bộ chính xác, không apply lặp hoặc stale effects.
- Equipment signals chỉ emit khi state thực sự thay đổi.
- Max HP và Current HP signals tuân thủ đúng điều kiện emit.
- Dynamic slots không làm ảnh hưởng equipment hiện có.
