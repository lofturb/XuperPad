//
//  XPCrypto.h
//  Cifrado y codificacion usados por el protocolo del portal.
//

#import <Foundation/Foundation.h>

/// Resultado de una operacion criptografica.
@interface XPCrypto : NSObject

/// Cifra o descifra con 3DES-EDE (3 claves, ECB, PKCS7).
+ (NSData *)tripleDesData:(NSData *)source
                  encrypt:(BOOL)encrypt
                    error:(NSError **)error;

/// Prepara el cuerpo de una peticion: hex( base64( 3DES( texto ) ) ).
+ (NSString *)encodeRequestBody:(NSString *)plainText error:(NSError **)error;

/// Lee el campo "data" de una respuesta: 3DES( base64( hex( ascii ) ) ).
+ (NSString *)decodeResponseBlob:(NSString *)blob error:(NSError **)error;

/// Digest MD5 en hexadecimal.
+ (NSString *)md5HexOfData:(NSData *)source;

/// Digest MD5 en hexadecimal de una cadena.
+ (NSString *)md5HexOfString:(NSString *)source;

/// Convierte bytes en cadena hexadecimal.
+ (NSString *)hexStringFromData:(NSData *)source;

/// Convierte cadena hexadecimal en bytes.
+ (NSData *)dataFromHexString:(NSString *)source;

/// Devuelve una cadena hexadecimal aleatoria de la longitud pedida en bytes.
+ (NSString *)randomHexStringOfByteCount:(NSUInteger)byteCount;

/// Devuelve una direccion MAC aleatoria con formato de dos digitos.
+ (NSString *)randomMacAddress;

@end
