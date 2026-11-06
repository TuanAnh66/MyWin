# Phân tích Ghost U12 và Superlite so với MyWin v5

Đây là kết quả kiểm tra **chỉ đọc** ISO `WIN11.PRO.25H2.U12.X64.(WPE).ISO` do người dùng cung cấp, build **26200.9711**. Không phải chứng thực nguồn phát hành hoặc độ an toàn của ISO, và không phải kết luận cho mọi phiên bản mang tên GhostSpectre.

## Báo cáo

- [Phân tích tổng thể 6 image](REPORT.txt): thành phần còn giữ, khác biệt Compact/Superlite/SE, chuỗi OOBE và cách đóng gói.
- [Phân tích script và đối chiếu v5](v5-comparison/ANALYSIS.txt): dịch vụ, registry, lần ghi đè, lệnh không nên chép và đề xuất cho v5.
- [Bảng dịch vụ Superlite ↔ v5](v5-comparison/v5-service-comparison.csv).
- [Bảng registry OOBE ↔ v5](v5-comparison/v5-registry-comparison.csv).
- [Bảng registry visual.cmd ↔ v5](v5-comparison/visual-v5-registry-comparison.csv).
- [Danh sách đề xuất để xem xét](v5-comparison/candidate-plan.json), **chưa áp dụng**.

## Phát hiện chính

1. Cả 6 image vẫn giữ .NET 32/64-bit, PowerShell, WoW64, WinRE, 19.424 thư mục payload WinSxS và 718 thư mục driver. MyWin v5 cắt sâu hơn.
2. Compact và Superlite có cùng danh sách đường dẫn; đối chiếu hash chỉ thấy 10 file khác nội dung, gồm hive/log registry, archive triển khai và một manifest. Xem [kết quả so sánh](data/image-content-comparison.json).
3. Khác biệt quan trọng nằm ở registry/SKU và các script OOBE. Superlite có `EditionID=ServerRdsh` dù nhãn image là Windows 11 Pro; SE bổ sung payload StartAllBack.
4. Script Superlite đặt 27 service targets: v5 đã có cùng cấu hình ở 10 mục; 6 dịch vụ không tồn tại; 11 mục khác. Không phải tất cả đều nên áp dụng: chép `WerSvc=3` sẽ làm ngược việc v5 đã Disabled, còn `SENS` nên được giữ.
5. Có thể thử thêm animation/transparency, policy Game DVR và dịch vụ chức năng không dùng. Chưa đo mức RAM giảm; dịch vụ Manual không đồng nghĩa đang chạy.

## Cách hiểu số liệu

Các giá trị v5 lấy từ hive trong WIM, không phải trạng thái chạy của VM đã cài. HKCU ở từng giai đoạn OOBE và Default User là các ngữ cảnh khác nhau. Dữ liệu HKCU được so với Default User v5 chỉ để tham khảo cho user mới.

Phân tích tĩnh bỏ dòng chú thích, xét nhánh SUPERLITE và đánh dấu lần ghi đè trong từng script. Helper chạy bất đồng bộ, lỗi lệnh và cấu hình phát sinh sau đăng nhập có thể thay đổi kết quả cuối. Không cài thử ISO, chạy Ghost Toolbox hoặc thực thi script/binary của bộ cài.

`data/` chứa tóm tắt, số lượng và khác biệt content. `v5-comparison/` chứa dữ liệu đối chiếu có cấu trúc. Các bảng registry công khai đã bỏ nguyên văn trường `Command` và các blob cache/binary dài; giữ thông tin dòng, hive/key/value và nhận xét. Đây là dữ liệu phân tích, không phải script tối ưu được phép chạy.

## Dữ liệu và công cụ không kèm theo

Không phân phối ISO/WIM, hive registry, EXE/DLL, archive payload hay script Ghost gốc. Các đường dẫn `payload-index-*`, `index-*`, `hives` và tên file source trong báo cáo là bằng chứng tại máy audit; chúng không tồn tại trong repo.

`tools/` chỉ gồm helper phân tích tự viết. Chúng vẫn tham chiếu workspace lịch sử `C:\tiny11-work\ghost-u12-audit` và helper `LiteV3Registry.cs`; cần chuẩn bị input ngoài repo hoặc chỉnh đường dẫn trước khi dùng. Các helper chỉ đọc/parse dữ liệu, không chạy script Ghost.

**Không có thay đổi nào với v5 WIM/ESD từ đợt nghiên cứu này.** Tạo v6 hoặc áp dụng candidate cần một yêu cầu triển khai riêng và kiểm chứng trong VM.
