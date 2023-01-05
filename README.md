# Compass SDK
Librería para la integración de medios digitales con la tecnología Compass de Marfeel.

## Características

- Tracking del tiempo de permanencia en una página
- Control del porcentaje de scroll
- Identificación de usuario
- Manejo de RFV
- Tracking de conversiones

## Instalación

La instalación se realiza mediante Cocoapods, añadiendo la siguiente línea al fichero Podfile

```ruby
pod 'CompassSDK', '~> 1'
```

## Configuración

Para utilizar la librería debe añadir la cuenta y el endpoint que le ha proveído Compass al registrar su cuenta. Dentro del fichero Info.plist añada las siguientes propiedades

```xml
<key>COMPASS_ACCOUNT_ID</key>
<integer>0</integer>
<key>COMPASS_ENDPOINT</key>
<string>https://events.newsroom.bi/</string>
```

Indicando en el campo COMPASS_ACCOUNT_ID su identificador de cuenta, y en COMPASS_ENDPOIT el endpoint que le han proporcionado.

## Uso

Para poder utilizar la librería, importe el módulo CompassSDK.

```swift
import CompassSDK
```

Todas las funcionalidades de la librería se realizan a través de la clase CompassTracker. Para acceder a CompassTracker simplemente use su variable shared en cualquier parte de la aplicación.

```swift
let tracker = CompassTracker.shared
```

### Tracking de páginas

CompassTracker se encarga automáticamente de controlar el tiempo que el usuario se mantiene en una página. Para indicar que comience el tracking de una página concreta use el método trackNewPage, indicando la url de la página.

```swift
tracker.trackNewPage(url: {URL})
```

CompassTracker continuará registrando el tiempo de permanencia en la página hasta que se llame de nuevo a trackNewPage con una url diferente. O bien si el desarrollador lo indica mediante el método stopTracking()

```swift
tracker.stopTracking()
```

### Control del scroll

Si quiere que el sistema registre el porcentaje de scroll que el usuario ha hecho en la página, indique en el método trackNewPage el UIScrollView en el que se está mostrando el contenido al usuario.

```swift
tracker.trackNewPage(url: {URL}, scrollView: {UIScrollView}})
```

### Identificación de usuario

Para asociar al usuario de la aplicación con los registros generados por la librería, utilice el método setSiteUserId, indicando el identificador del usuario en su plataforma.

```swift
tracker.setSiteUserId({USER_ID})
```

Adicionalmente, puede indicar el tipo de usuario, actualmente la librería permite los tipos logged (para usuarios registrados) y paid (para usuarios de pago). Para indicar el tipo de usuario use el método setUserType.

```swift
tracker.setUserType(.unknwon)

tracker.setUserType(.anonymous)

tracker.setUserType(.paid)

tracker.setUserType(.logged)

tracker.setUserType(.custom(9))
```

Es recomendable que indique el identificador y el tipo de usuario antes de realizar el primer tracking.

### Manejo de RFV

Si quiere obtener el código RFV de Compass utilice el método getRFV. Este método devuelve el código RFV mediante un handler.

```swift
tracker.getRFV { rfv in
//Manejo del rfv recibido
}
```

### Tracking de conversiones

Si quiere indicar una conversión, puede llamar en cualquier momento al método trackConversion(conversion: String).

```swift
tracker.trackConversion(conversion: "{CONVERSION}"
```
