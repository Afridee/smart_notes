# flutter_gemma / MediaPipe: framework references optional protobuf types that are not
# present in the shipped AARs. R8 reports them as missing unless suppressed.
# See build output: outputs/mapping/release/missing_rules.txt
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate
