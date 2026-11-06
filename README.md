# MyWin

Script và hồ sơ thử nghiệm tạo Windows 11 Pro **26300.9818** gọn nhẹ từ bộ cài UUP, dựa trên quy trình tiny11builder.

Trạng thái hiện tại: **v5**, giữ .NET Framework, Windows PowerShell, WoW64 và 6 driver VirtIO. WIM LZX có kích thước **2,553,729,069 bytes (2,38 GiB)**; ESD solid LZMS còn **1,769,795,512 bytes (1,65 GiB)**, giảm **30,70%**. WIM nguồn giữ nguyên checksum. Người dùng đã thử khởi động vào desktop và mở Task Manager trong VMware.

## Bắt đầu đọc

- [Bàn giao đầy đủ v1–v5](docs/HANDOFF.txt): các mốc, script, checksum, lỗi đã gặp và cách tiếp tục.
- [Cách dùng các script](docs/WORKFLOW.md): môi trường, đường dẫn cố định và dữ liệu cần chuẩn bị.
- [Báo cáo WIM v5](reports/lite-v5.json), [báo cáo ESD v5](reports/lite-v5-esd.json), [font đã gỡ](reports/v5-removed-font-files.txt).
- [Phân tích Ghost U12/Superlite và đối chiếu với v5](research/ghost-u12/README.md): thành phần giữ lại, dịch vụ, registry và các đề xuất chưa áp dụng.
- [Nguồn và phạm vi repository](NOTICE.md).

## Các mốc

| Bản | Kết quả | WIM LZX | ESD LZMS |
|---|---|---:|---:|
| v1/v2 | Core cực hạn; thiếu .NET/WoW64, phát sinh lỗi PowerShell | Xem hồ sơ | — |
| v3 | Dựng lại, giữ .NET/PowerShell/WoW64 | 3,38 GiB | — |
| v4 | Cắt tiếp WinSxS và driver dư; đã thử VMware/PowerShell | 3,20 GiB | 2,27 GiB |
| v4 + VirtIO | Thêm balloon, NetKVM, vioscsi, viostor, vioser, viorng | 3,20 GiB | 2,28 GiB |
| v5 | Bỏ WebView2 runtime/SDK, 23 file font CJK và SecureBootUpdates | **2,38 GiB** | **1,65 GiB** |

ESD v5 được nén lại toàn bộ với LZMS, solid chunk 16 MiB, 8 luồng; mất **13,03 phút** gồm kiểm chứng của script. Kiểm tra toàn vẹn mọi file, metadata, danh sách đường dẫn và DISM đọc index 1 đều đạt. SHA-256 ESD: `C90704DC0C289876F666B3E544DBE96488E1B02A3319D72E925F70D8B436E53D`.

Các artifact Windows được giữ trên máy build, **không có trong repository**. Repository chỉ chứa script tự viết, recipe, metadata kiểm chứng và tài liệu. Không chứa ISO/WIM/ESD, registry hive, driver/binary Microsoft, MSI hay SSH key.

## Điểm cần biết trước khi chạy

- Đây là bản lưu quy trình đã thực hiện trên máy Windows, **chưa phải công cụ portable chạy một lệnh**. Nhiều script cố định `C:\tiny11-work`, `C:\26300.9818` và build 26300.9818; đọc script trước khi dùng.
- Các bản Core đã cắt servicing/component store: không bảo đảm cài Windows Update, MSU/CAB, DISM repair hoặc System Restore hoạt động.
- v5 giữ nguyên hash các file .NET/PowerShell/WoW64/VirtIO so với nguồn; kiểm tra toàn vẹn WIM đạt. Boot VMware thành công chưa chứng minh mọi ứng dụng hoặc boot KVM/VPS thành công.
- Đã bỏ cả DLL WebView2 trong một số app: cài lại Evergreen runtime có thể chưa đủ, app có thể cần repair/reinstall.
- Tạo bản mới ở thư mục riêng; giữ WIM nguồn. Không chạy lại script lên output đã hoàn tất. Không tự cắt thêm những mục mới chỉ được nêu như gợi ý trong hồ sơ.

## Nguồn tham khảo

- [ntdevlabs/tiny11builder](https://github.com/ntdevlabs/tiny11builder) — checkout được dùng khi bắt đầu: `38f7ab6` trên nhánh `winui-preview`.
- [wimlib](https://wimlib.net/) — thao tác WIM/ESD và kiểm chứng dữ liệu.
- [virtio-win](https://github.com/virtio-win/virtio-win-pkg-scripts) — driver Windows 11 amd64, phiên bản 0.1.302.

Repository này không phải dự án chính thức của Microsoft, ntdevlabs hay virtio-win. Quyền sử dụng Windows và công cụ/driver tải riêng tuân theo giấy phép tương ứng.
