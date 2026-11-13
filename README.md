# VT-110 – Idempotency

Bài tập Software Engineering cá nhân, biến thể **VT-110 (Idempotency)** trên dự án GAME-2D-02: Procedural Dungeon.

Mục tiêu: đảm bảo `start_new_run()` xử lý request lặp có cùng request ID và payload mà không tạo run, record hoặc signal trùng lặp.

## 1. Môi trường

- Godot `4.7.2`
- GDScript
- Headless testing

## 2. Cấu trúc liên quan

Các file nằm trong `procedural-dungeon/`:

```text
scripts/run_management/
├── run_manager.gd
└── run_record_repository.gd

tests/
├── test_run_manager.gd
├── run_tests.gd
└── load_test_vt110.gd
```

## 3. Chạy test

Mở Terminal tại thư mục `procedural-dungeon/`:

```bash
godot --headless --path . -s res://tests/run_tests.gd
```

Kết quả kiểm thử được ghi nhận:

```text
Tests: 50
Passed: 50
Failed: 0
```

Thông báo lỗi lưu trữ trong `test_storage_failure_blocks_run_start` là tình huống được cố ý tạo để kiểm tra failure handling; test vẫn PASS.

## 4. Load test

```bash
godot --headless --path . -s res://tests/load_test_vt110.gd
```

Thử nghiệm gồm 120 request logic xử lý tuần tự trên một manager, không phải concurrency thực. Kết quả queued response p95 là **3.767971 giây**, vượt mục tiêu 3.5 giây.

## 5. Thông tin repository

- Repository: https://github.com/Des19305/SE2026.02.2
- Submission branch: [assignment/vt110-idempotency](https://github.com/Des19305/SE2026.02.2/tree/assignment/vt110-idempotency)
- Baseline: `e6bf4d7`
- Implementation integration: `63dba4b`
- Final submission HEAD: [`42ab2dc`](https://github.com/Des19305/SE2026.02.2/commit/42ab2dc53ddae06dc989ffcd4b58c8a7a2d97988)

Mutation experiment nằm trên branch riêng [mutation/vt110-response-mapping](https://github.com/Des19305/SE2026.02.2/tree/mutation/vt110-response-mapping), commit `2a6c350`; không thuộc submission branch.
