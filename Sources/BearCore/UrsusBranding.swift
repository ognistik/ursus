import Foundation

public enum UrsusBranding {
    public static let serverName = "ursus"
    public static let serverTitle = "Ursus"
    public static let lightThemeForeground = "#242522"
    public static let darkThemeForeground = "#f0f0ed"
    public static let svgMIMEType = "image/svg+xml"

    public static func logoSVG(fillColor: String = "currentColor") -> String {
        """
        <svg viewBox="0 0 462.56 413.17" fill="\(fillColor)" xmlns="http://www.w3.org/2000/svg">
          <path d="M254.01 122.12s-79.38 44.49-115.95 66.62l-85.94 15.39c-1.1-1.5 69.48-122.36 71.54-122.91l130.35 40.9Z"/>
          <path d="M114.41 73.99l66.85-45.58c31.58 2.32 63.23 3.51 94.82 5.37-7.04 2.24-110.37 28.08-163.44 42.78l-48.31 44.74-19.2-85.4c7.62-6.58 15.59-12.93 23.61-19 3.6-2.72 14.57-10.78 23.37-16.9 20.7 8.02 47.26 18.93 65.67 27.09l-43.38 46.9Z"/>
          <path d="M247.26 349.81L58.42 208.87l77.32-11.44 111.52 152.38Z"/>
          <path d="M410.56 131.56l-8.72-32.29-30.25-24.21 6.65-27.86-38.38-20.37c-12.57 3.57-192.28 51.84-192.28 51.84l112.53 37.22 50.95 34.56-49.93-20.4-115.95 63.85.72 2.02c22.74 33.31 140.44 195.13 140.44 195.13S104.87 247.35 43.57 208.72l19.54-82.96C33.23 181.52-.41 237.83 0 239.87l304.41 173.3-40.76-89.49c-.83.3 146.2-58.92 146.2-58.92l49.35-56.22 3.35-42.21c-17.21-11.8-36.22-20.95-52-34.75Z"/>
        </svg>
        """
    }

    public static func logoDataURI(fillColor: String) -> String {
        let payload = Data(logoSVG(fillColor: fillColor).utf8).base64EncodedString()
        return "data:\(svgMIMEType);base64,\(payload)"
    }
}
