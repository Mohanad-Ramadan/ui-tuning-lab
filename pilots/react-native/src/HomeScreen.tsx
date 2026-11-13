import { Text, View } from "react-native";
import { CardList } from "./CardList";
import { cardDefaults } from "./cards";

export function HomeScreen() {
  return (
    <View style={{ flex: 1, padding: 16 }}>
      <Text style={{ fontSize: 28, fontWeight: "700" }}>Home</Text>
      <CardList config={cardDefaults} />
    </View>
  );
}
