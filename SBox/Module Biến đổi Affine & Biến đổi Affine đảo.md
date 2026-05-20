## Module Biến đổi Affine 
### 1. High level Block Design
![[Affine high level.png]]

| Tín hiệu            | Hướng  | Độ rộng | Mô tả                                                             |
| :------------------ | :----- | :------ | :---------------------------------------------------------------- |
| `byte_a_mInv`       | Input  | 8 bit   | Byte đầu vào                                                      |
| `byte_a_substitute` | Output | 8 bit   | Byte đầu ra sau khi biến đổi Affine chính là kết quả tra cứu SBox |
### 2. Low level Block Design
![[Affine low level.png]]
## Module Biến đổi Affine đảo
### 1. High level Block Design
![[Affine dao high level.png]]

| Tín hiệu     | Hướng  | Độ rộng | Mô tả                                   |
| :----------- | :----- | :------ | :-------------------------------------- |
| `byte_a`     | Input  | 8 bit   | Byte đầu vào                            |
| `byte_a_aff` | Output | 8 bit   | Byte đầu ra sau khi biến đổi Affine đảo |
### 2. Low level Block Design
![[Affine dao low level.png]]
