## Module Biến đổi Affine 
### 1. High level Block Design
![[../../../_media/Affine high level.png]]

| Tín hiệu   | Hướng  | Độ rộng | Mô tả                                                             |
| :--------- | :----- | :------ | :---------------------------------------------------------------- |
| `byte_in`  | Input  | 8 bit   | Byte đầu vào                                                      |
| `byte_out` | Output | 8 bit   | Byte đầu ra sau khi biến đổi Affine chính là kết quả tra cứu SBox |
### 2. Low level Block Design
![[../../../_media/Affine low level.png]]
## Module Biến đổi Affine đảo
### 1. High level Block Design
![[../../../_media/Affine dao high level.png]]

| Tín hiệu   | Hướng  | Độ rộng | Mô tả                                   |
| :--------- | :----- | :------ | :-------------------------------------- |
| `byte_in`  | Input  | 8 bit   | Byte đầu vào                            |
| `byte_out` | Output | 8 bit   | Byte đầu ra sau khi biến đổi Affine đảo |
### 2. Low level Block Design
![[../../../_media/Affine dao low level.png]]
