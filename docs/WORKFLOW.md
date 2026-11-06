# Triển khai tiếp từ hồ sơ

## Môi trường

Chạy trên Windows, PowerShell 7 cho các script build có `ProcessStartInfo.ArgumentList`. Các script sửa registry qua `offreg.dll` x86 phải chạy bằng Windows PowerShell **32-bit**; script build đã gọi đúng executable khi cần.

Các đường dẫn lịch sử:

| Đường dẫn | Chức năng |
|---|---|
| `C:\tiny11-work` | Script, helpers và thư mục build |
| `C:\26300.9818\bin` | wimlib-imagex, 7z và offreg.dll x86, tải riêng |
| `C:\tiny11-work\lite-v3` | Nguồn giữ runtime |
| `C:\tiny11-work\lite-v4` | WIM/ESD v4 |
| `C:\tiny11-work\lite-v4-virtio` | WIM/ESD có VirtIO, input MSI/driver tải riêng |
| `C:\tiny11-work\lite-v5` | WIM LZX và ESD LZMS v5 đã hoàn thành |

Repo `MyWin` là bản lưu source riêng. Việc clone repo **không** tự tạo các image, hives, inventory hay mount cần thiết. Không copy toàn bộ repo vào output folder của một build rồi chạy vì nhiều script từ chối thư mục đã tồn tại. Giữ script tại build workspace hoặc chỉnh các đường dẫn trong một nhánh riêng trước khi triển khai.

## Thứ tự lịch sử

1. UUP converter tích hợp cập nhật trước: `uup-minimal/ConvertConfig.ini`, `Rebuild-FromCache.ps1`. Dùng cache của người dùng, không có trong repo.
2. v3: `Build-LiteV3-Service.ps1` → `Finish-LiteV3.ps1`, có `Configure-LiteV3-Hives.ps1` và helper `app-metadata-cleanup/OfflineAppMetadata.cs`. Xem hồ sơ về DISM qua scheduled task khi gặp initialization error.
3. v4: `Build-LiteV4.ps1` → sửa/kiểm tra driver metadata bằng `Clean-LiteV4-DriverDatabase.ps1`, `Finalize-LiteV4-DriverMetadata.ps1`. Cần inventory INF từ image nguồn và danh sách tham chiếu; các metadata chọn lọc nằm trong `snapshots/`. Đây không phải toàn bộ dữ liệu đầu vào dựng lại v4 từ đầu.
4. VirtIO: tải MSI từ nguồn đã ghi trong hồ sơ, giải nén bằng 7z; `Prepare-VirtIO-V4.ps1` đọc bảng File MSI qua `ReadMsiFiles.cs`. `Build-V4-VirtIO-Service.ps1` tích hợp driver bằng DISM, `Finish-V4-VirtIO.ps1` kiểm tra payload/signature/registry. Không execute MSI để chuẩn bị input.
5. v5: `Build-LiteV5.ps1` gọi `Clean-V5-Registry.ps1`, lấy nguồn v4 VirtIO đúng checksum. Gỡ payload trên bản sao; xuất LZX, verify toàn bộ WIM, đối chiếu mọi file còn giữ. Script cố ý từ chối chạy nếu folder v5 đã có.

## Nếu muốn tạo bản mới

Đọc `HANDOFF.txt` trước. Copy script thành bản mới với root mới, chọn nguồn/checksum rõ ràng. Không chỉ đổi tên output rồi chạy lại logic vốn phụ thuộc snapshot của build cũ. Bảo vệ .NET, assembly/GAC, SysWOW64, PowerShell và VirtIO. Tách kiểm tra hash offline khỏi kiểm chứng boot/app thực tế.

V5 đã nén ESD thành công bằng `Compress-LiteV4.ps1 -Root C:\tiny11-work\lite-v5 -ImageLabel v5`, **không dùng `-SeedEsd`**. File ESD cuối 1.769.795.512 bytes; WIM nguồn giữ nguyên. Xem [báo cáo](../reports/lite-v5-esd.json).

Thử dùng lại seed ESD VirtIO chỉ giảm 4,10% so với WIM vì các solid block còn giữ dữ liệu đã bị cắt khỏi v5. Nén lại toàn bộ mới giảm 30,70%. Seed reuse thích hợp với thay đổi nhỏ như thêm driver; khi xóa nhiều payload, cần cân nhắc full recompression. Script từ chối output đã tồn tại: không chạy lại lệnh trên thư mục v5 đã hoàn tất nếu chưa chuẩn bị thư mục/output mới.

## Nội dung không được đưa vào Git

Windows ISO/WIM/ESD/VHD, driver SYS/CAT, binary công cụ, MSI, registry SOFTWARE/SYSTEM/DRIVERS/NTUSER, dữ liệu credential, log chứa dữ liệu máy và cache tải. Lấy công cụ/media từ nguồn tương ứng và giữ ngoài repo. Các snapshots trong repo chỉ là danh sách đường dẫn/hash/JSON để truy vết.
