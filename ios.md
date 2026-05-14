# Integracion Marfeel: trackConversion

Este documento resume como esta implementada la llamada a `trackConversion` de Marfeel en Android e iOS, que valor se envia como `options.id`, y ejemplos reconstruidos a partir de los exports de Firebase.

## Resumen tecnico

La conversion se dispara despues de una compra exitosa no duplicada desde:

`lib/src/features/feature_paywall/presentation/pages/paywall_complete_screen.dart`

```dart
final marfeelConversionResult =
    await MarfeelService.trackConversion(transactionId: transactionId, value: purchaseValue, termId: termId);
```

Luego `MarfeelService.trackConversion` arma el payload que viaja por MethodChannel hacia Android o iOS:

`lib/src/features/feature_marfeel/marfeel_service.dart`

```dart
final normalizedTermId = termId.trim();

final meta = <String, String>{
  'transaction': normalizedTransactionId,
  if (normalizedTermId.isNotEmpty) 'term_id': normalizedTermId,
};

final params = <String, Object>{
  "id": normalizedTransactionId,
  "value": value,
  "meta": meta,
};

final result = await _channel.invokeMethod('trackConversion', params);
```

## 1. Codigo implementado en Android e iOS para llamar a trackConversion

### Android

Archivo:

`android/app/src/main/kotlin/co/kubo/eltiempo/MarfeelPlugin.kt`

Codigo relevante:

```kotlin
val id = call.argument<String>("id")
val meta = call.argument<HashMap<String, String>>("meta") ?: hashMapOf()
val rawValue = call.argument<Any>("value")
val normalizedId = id.trimToNonEmpty()
val value = rawValue?.toString().trimToNonEmpty()

if (normalizedId == null) {
    result.success(
        conversionFailure(
            reason = "missing_transaction_id",
            stage = "pre_validation",
            detail = "id es requerido"
        )
    )
    return
}

if (rawValue == null) {
    result.success(
        conversionFailure(
            reason = "missing_value",
            stage = "pre_validation",
            detail = "value es requerido"
        )
    )
    return
}

if (value == null) {
    result.success(
        conversionFailure(
            reason = "invalid_value",
            stage = "pre_validation",
            detail = "value no puede estar vacio"
        )
    )
    return
}

tracker?.setPageVar("VersionAppContenido", BuildConfig.VERSION_NAME)
tracker?.setPageVar("hasSuscription", "true")

val options = ConversionOptions(
    id = normalizedId,
    value = value,
    meta = meta,
    scope = ConversionScope.User
)

tracker?.trackConversion("subscribe", options)
```

Puntos clave:

- El evento de conversion enviado a Marfeel es `"subscribe"`.
- `options.id` recibe `normalizedId`, que viene de `params["id"]` enviado desde Dart.
- `options.value` se convierte a `String` en Android con `rawValue?.toString()`.
- `options.meta` incluye al menos `transaction`; si hay `termId`, tambien incluye `term_id`.
- El scope enviado es `ConversionScope.User`.

### iOS

Archivo:

`ios/Runner/MarfeelBridge/MarfeelBridge.swift`

Codigo relevante:

```swift
guard let rawId = args["id"] as? String else {
    result(self.conversionFailure(
        reason: "missing_transaction_id",
        stage: "pre_validation",
        detail: "id is required"
    ))
    return
}

let id = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
if id.isEmpty {
    result(self.conversionFailure(
        reason: "missing_transaction_id",
        stage: "pre_validation",
        detail: "id is empty"
    ))
    return
}

guard let rawValue = args["value"] else {
    result(self.conversionFailure(
        reason: "missing_value",
        stage: "pre_validation",
        detail: "value is required"
    ))
    return
}

let value: String
if let stringValue = rawValue as? String {
    value = stringValue
} else if let numberValue = rawValue as? NSNumber {
    value = numberValue.stringValue
} else {
    value = "\(rawValue)"
}

let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
if normalizedValue.isEmpty {
    result(self.conversionFailure(
        reason: "invalid_value",
        stage: "pre_validation",
        detail: "value cannot be empty"
    ))
    return
}

let meta = args["meta"] as? [String: String]
self.tracker.setPageVar(name: "hasSuscription",  value: "true")
self.tracker.setPageVar(name: "VersionAppContenido",  value: appVersion)

let options = ConversionOptions(
    id: id,
    value: normalizedValue,
    meta: meta,
    scope: .user
)

self.tracker.trackConversion(conversion: "subscribe", options: options)
```

Puntos clave:

- El evento de conversion enviado a Marfeel es `"subscribe"`.
- `options.id` recibe `id`, que viene de `args["id"]` enviado desde Dart.
- `options.value` se normaliza a `String`.
- `options.meta` se lee como `[String: String]`.
- El scope enviado es `.user`.

## 2. Que valor se esta enviando como options.id

`options.id` recibe el `transactionId` de la compra.

La resolucion se hace antes de llegar a Marfeel. En el flujo de paywall, `_lastTransactionId` se define con esta prioridad:

`lib/src/features/feature_paywall/presentation/providers/paywall_provider.dart`

```dart
_lastTransactionId = nativePurchaseData?.transactionId ??
    nativePurchaseData?.originalTransactionId ??
    purchaseDetails.purchaseID ??
    '';
```

Luego ese valor viaja en `completionData`:

```dart
return <String, dynamic>{
  'transactionId': transactionId,
  'value': value,
  'termId': termId,
};
```

Y finalmente Marfeel lo usa como `"id"`:

```dart
final params = <String, Object>{
  "id": normalizedTransactionId,
  "value": value,
  "meta": meta,
};
```

Conclusion:

- `options.id` = `transactionId` normalizado.
- En Android suele ser el `GPA...` de Google Play, por ejemplo `GPA.3306-1021-1679-89252`.
- En iOS suele ser el transaction id numerico de StoreKit, por ejemplo `2000001164338457`.
- No se envia `termId` como `options.id`; `termId` se envia dentro de `options.meta["term_id"]`.

## Ejemplo Android

Llamado equivalente en Android:

```kotlin
tracker?.setPageVar("VersionAppContenido", BuildConfig.VERSION_NAME)
tracker?.setPageVar("hasSuscription", "true")

val options = ConversionOptions(
    id = "GPA.3306-1021-1679-89252",
    value = "177900.0",
    meta = hashMapOf(
        "transaction" to "GPA.3306-1021-1679-89252",
        "term_id" to "TM1DDESNY1XH"
    ),
    scope = ConversionScope.User
)

tracker?.trackConversion("subscribe", options)
```

## Ejemplo iOS

Llamado equivalente en iOS:

```swift
self.tracker.setPageVar(name: "hasSuscription", value: "true")
self.tracker.setPageVar(name: "VersionAppContenido", value: appVersion)

let options = ConversionOptions(
    id: "2000001164338457",
    value: "27900",
    meta: [
        "transaction": "2000001164338457",
        "term_id": "TMLR8ISRTEMY"
    ],
    scope: .user
)

self.tracker.trackConversion(conversion: "subscribe", options: options)
```