import { CardList } from "./CardList";
import { cardDefaults } from "./cards";

export function HomeScreen() {
  return (
    <main>
      <h1>Home</h1>
      <CardList config={cardDefaults} />
    </main>
  );
}
