
### TC1: NIST TC2 (Zero Vector, Không AAD)
| Tham số                 |     Kích thước     | Giá trị Hexadecimal                |
| :---------------------- | :----------------: | :--------------------------------- |
| **Cipher Key**          | 16 Bytes (128-bit) | `00000000000000000000000000000000` |
| **IV**                  | 12 Bytes (96-bit)  | `000000000000000000000000`         |
| **AAD**                 |       0 Byte       | *(Không có - `no_AAD = 1`)*        |
| **Plaintext**           | 16 Bytes (128-bit) | `00000000000000000000000000000000` |
| **Expected Ciphertext** | 16 Bytes (128-bit) | `0388dace60b6a392f328c2b971b2fe78` |
| **Expected Tag**        | 16 Bytes (128-bit) | `ab6e47d42cec13bdf53a67b21257bddf` |

### TC2: NIST TC3 (Multi-block 64B, Không AAD)
| Tham số                 |     Kích thước     | Giá trị Hexadecimal                                                                                                                |
| :---------------------- | :----------------: | :--------------------------------------------------------------------------------------------------------------------------------- |
| **Cipher Key**          | 16 Bytes (128-bit) | `feffe9928665731c6d6a8f9467308308`                                                                                                 |
| **IV**                  | 12 Bytes (96-bit)  | `cafebabefacedbaddecaf888`                                                                                                         |
| **AAD**                 |       0 Byte       | *(Không có - `no_AAD = 1`)*                                                                                                        |
| **Plaintext**           | 64 Bytes (512-bit) | `d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255` |
| **Expected Ciphertext** | 64 Bytes (512-bit) | `42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985` |
| **Expected Tag**        | 16 Bytes (128-bit) | `4d5c2af327cd64a62cf35abd2ba6fab4`                                                                                                 |

### TC3: 1 Block AAD + 1 Block PT
| Tham số | Kích thước | Giá trị Hexadecimal |
|:---|:---:|:---|
| **Cipher Key** | 16 Bytes (128-bit) | `feffe9928665731c6d6a8f9467308308` |
| **IV** | 12 Bytes (96-bit) | `cafebabefacedbaddecaf888` |
| **AAD** | 16 Bytes (128-bit) | `feedfacedeadbeeffeedfacedeadbeef` |
| **Plaintext** | 16 Bytes (128-bit) | `d9313225f88406e5a55909c5aff5269a` |
| **Expected Ciphertext** | 16 Bytes (128-bit) | `42831ec2217774244b7221b784d0d49c` |
| **Expected Tag** | 16 Bytes (128-bit) | `803a17709e281bcbd7e920f13cf41505` |

### TC4: 2 Blocks AAD + 2 Blocks PT
| Tham số | Kích thước | Giá trị Hexadecimal |
|:---|:---:|:---|
| **Cipher Key** | 16 Bytes (128-bit) | `feffe9928665731c6d6a8f9467308308` |
| **IV** | 12 Bytes (96-bit) | `cafebabefacedbaddecaf888` |
| **AAD** | 32 Bytes (256-bit) | `feedfacedeadbeeffeedfacedeadbeef0123456789abcdef0123456789abcdef` |
| **Plaintext** | 32 Bytes (256-bit) | `d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72` |
| **Expected Ciphertext** | 32 Bytes (256-bit) | `42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e` |
| **Expected Tag** | 16 Bytes (128-bit) | `7d708e94035dc6f378cefd3ab5e8973f` |

### TC5: GMAC (Chỉ có AAD, Không Plaintext)
| Tham số | Kích thước | Giá trị Hexadecimal |
|:---|:---:|:---|
| **Cipher Key** | 16 Bytes (128-bit) | `feffe9928665731c6d6a8f9467308308` |
| **IV** | 12 Bytes (96-bit) | `cafebabefacedbaddecaf888` |
| **AAD** | 16 Bytes (128-bit) | `feedfacedeadbeeffeedfacedeadbeef` |
| **Plaintext** | 0 Byte | *(Không có)* |
| **Expected Ciphertext** | 0 Byte | *(Không có)* |
| **Expected Tag** | 16 Bytes (128-bit) | `54df474f4e71a9ef8a09bf30da7b1a92` |

---

## 3. Bảng chi tiết: AES-256-GCM

### TC6: NIST TC14 (Zero Vector, Không AAD)
| Tham số | Kích thước | Giá trị Hexadecimal |
|:---|:---:|:---|
| **Cipher Key** | 32 Bytes (256-bit) | `0000000000000000000000000000000000000000000000000000000000000000` |
| **IV** | 12 Bytes (96-bit) | `000000000000000000000000` |
| **AAD** | 0 Byte | *(Không có - `no_AAD = 1`)* |
| **Plaintext** | 16 Bytes (128-bit) | `00000000000000000000000000000000` |
| **Expected Ciphertext** | 16 Bytes (128-bit) | `cea7403d4d606b6e074ec5d3baf39d18` |
| **Expected Tag** | 16 Bytes (128-bit) | `d0d1c8a799996bf0265b98b5d48ab919` |

### TC7: NIST TC15 (Multi-block 64B, Không AAD)
| Tham số | Kích thước | Giá trị Hexadecimal |
|:---|:---:|:---|
| **Cipher Key** | 32 Bytes (256-bit) | `feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308` |
| **IV** | 12 Bytes (96-bit) | `cafebabefacedbaddecaf888` |
| **AAD** | 0 Byte | *(Không có - `no_AAD = 1`)* |
| **Plaintext** | 64 Bytes (512-bit) | `d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255` |
| **Expected Ciphertext** | 64 Bytes (512-bit) | `522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662898015ad` |
| **Expected Tag** | 16 Bytes (128-bit) | `b094dac5d93471bdec1a502270e3cc6c` |

### TC8: 1 Block AAD + 1 Block PT
| Tham số                 |     Kích thước     | Giá trị Hexadecimal                                                |
| :---------------------- | :----------------: | :----------------------------------------------------------------- |
| **Cipher Key**          | 32 Bytes (256-bit) | `feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308` |
| **IV**                  | 12 Bytes (96-bit)  | `cafebabefacedbaddecaf888`                                         |
| **AAD**                 | 16 Bytes (128-bit) | `feedfacedeadbeeffeedfacedeadbeef`                                 |
| **Plaintext**           | 16 Bytes (128-bit) | `d9313225f88406e5a55909c5aff5269a`                                 |
| **Expected Ciphertext** | 16 Bytes (128-bit) | `522dc1f099567d07f47f37a32a84427d`                                 |
| **Expected Tag**        | 16 Bytes (128-bit) | `03a2864be371e37753a80e8e240ff2f0`                                 |

### TC9: 2 Blocks AAD + 4 Blocks PT
| Tham số | Kích thước | Giá trị Hexadecimal |
|:---|:---:|:---|
| **Cipher Key** | 32 Bytes (256-bit) | `feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308` |
| **IV** | 12 Bytes (96-bit) | `cafebabefacedbaddecaf888` |
| **AAD** | 32 Bytes (256-bit) | `feedfacedeadbeeffeedfacedeadbeef0123456789abcdef0123456789abcdef` |
| **Plaintext** | 64 Bytes (512-bit) | `d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255` |
| **Expected Ciphertext** | 64 Bytes (512-bit) | `522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662898015ad` |
| **Expected Tag** | 16 Bytes (128-bit) | `dabd496a9b4ec0f24be49e6667b3a235` |

### TC10: GMAC (Chỉ có AAD, Không Plaintext)
| Tham số | Kích thước | Giá trị Hexadecimal |
|:---|:---:|:---|
| **Cipher Key** | 32 Bytes (256-bit) | `feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308` |
| **IV** | 12 Bytes (96-bit) | `cafebabefacedbaddecaf888` |
| **AAD** | 16 Bytes (128-bit) | `feedfacedeadbeeffeedfacedeadbeef` |
| **Plaintext** | 0 Byte | *(Không có)* |
| **Expected Ciphertext** | 0 Byte | *(Không có)* |
| **Expected Tag** | 16 Bytes (128-bit) | `d17d884a0dc9a437aeb28d77fc6bfbca` |

---

## 4. Test Case Giải mã & Xác thực (Decryption & Verify)

### TC11: Giải mã hợp lệ (`verify_pass = 1`)
| Tín hiệu đầu vào | Giá trị Hexadecimal |
|:---|:---|
| **`cipher_key`** | `feffe9928665731c6d6a8f9467308308` |
| **`IV`** | `cafebabefacedbaddecaf888` |
| **`AAD`** | `feedfacedeadbeeffeedfacedeadbeef` |
| **`data_in` (Ciphertext)** | `42831ec2217774244b7221b784d0d49c` |
| **`tag_ref` (Tag đối chiếu)** | `803a17709e281bcbd7e920f13cf41505` |

| Tín hiệu đầu ra | Giá trị kỳ vọng |
|:---|:---|
| **`data_out` (Plaintext)** | `d9313225f88406e5a55909c5aff5269a` |
| **`tag`** | `803a17709e281bcbd7e920f13cf41505` |
| **`verify_pass`** | **`1'b1`** *(Hợp lệ)* |

### TC12: Dữ liệu bị giả mạo (`verify_pass = 0`)
| Tín hiệu đầu vào | Giá trị Hexadecimal |
|:---|:---|
| **`data_in` (Ciphertext sai 1 bit)** | `42831ec2217774244b7221b784d0d49d` *(Byte cuối: `9c` $\rightarrow$ `9d`)* |
| **`tag_ref`** | `803a17709e281bcbd7e920f13cf41505` |

| Tín hiệu đầu ra | Giá trị kỳ vọng |
|:---|:---|
| **`verify_pass`** | **`1'b0`** *(Thất bại - Dữ liệu bị sửa đổi)* |
| **`verify_done`** | `1'b1` |
