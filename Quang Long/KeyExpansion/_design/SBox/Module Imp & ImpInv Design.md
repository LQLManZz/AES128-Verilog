## Module Imp
### 1. High level Block Design
![[../../../_media/Imp & ImpInv high level.png]]

| Tín hiệu   | Hướng  | Độ rộng | Mô tả                                    |
| :--------- | :----- | :------ | :--------------------------------------- |
| `byte_in`  | Input  | 8 bit   | Byte đầu vào                             |
| `byte_out` | Output | 8 bit   | Byte đầu ra sau khi đã ánh xạ thành công |
## 2. Low level Block Design 
![[../../../_media/Imp low level.png]]

## Module ImpInv

### 1. High level Block Design
![[../../../_media/ImpInv high level.png]]

| Tín hiệu   | Hướng  | Độ rộng | Mô tả                                                                    |
| :--------- | :----- | :------ | :----------------------------------------------------------------------- |
| `byte_in`  | Input  | 8 bit   | Byte đầu vào sau khi đã tính nghịch đảo                                  |
| `byte_out` | Output | 8 bit   | Byte đầu ra cũng chính là kết quả nghịch đảo nhân trong trường $GF(2^8)$ |
### 2. Low level Block Design
![[../../../_media/ImpInv low level.png]]