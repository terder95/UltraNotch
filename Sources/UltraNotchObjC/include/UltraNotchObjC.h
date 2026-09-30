// UltraNotch — ayudante en Objective-C.
// Swift no puede atrapar las "excepciones" de Objective-C (NSException). Algunas
// funciones de Apple las lanzan (por ejemplo el micrófono cuando cambias de audífonos).
// Si se escapan, AppKit se las traga pero deja a Swift en mal estado y la app se cierra
// más tarde. Con esto las atrapamos justo donde pasan.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Corre `block`. Si lanza una NSException, la atrapa y regresa NO (con la razón en `error`).
BOOL UltraNotchTryObjC(NS_NOESCAPE void (^block)(void), NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
