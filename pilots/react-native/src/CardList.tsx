import { Text, View } from "react-native";
import { cards } from "./cards";
import type { CardConfig } from "./cards";

export function CardList({ config }: { config: CardConfig }) {
  return (
    <View style={{ gap: config.gap }}>
      {cards.map(card => (
        <View key={card.title}
          style={{ borderRadius: config.radius, padding: config.padding, backgroundColor: "#eee" }}>
          <Text style={{ fontWeight: "600" }}>{card.title}</Text>
          <Text>{card.body}</Text>
        </View>
      ))}
    </View>
  );
}
