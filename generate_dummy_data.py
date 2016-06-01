import sys
import random
import predictionio

FILE_NAME = 'dummy_data.json'
MAX_USER = 20000000
MAX_REPO = 50000000

def main():
    exporter = new_exporter(FILE_NAME)
    for user_id in range(MAX_USER):
        items = new_items()
        print 'user {} has {} items'.format(user_id, len(items))
        for item_id in items:
             new_event(exporter, user_id, item_id)
    exporter.close()

def new_exporter(file_name):
    return predictionio.FileExporter(file_name=file_name)

def new_items():
    item_count = new_item_count()
    sample = [new_item_id() for _ in range(item_count)]
    return list(set(sample)) # dedupe

def new_item_count():
    return int(random.betavariate(0.3, 0.5) * 100)

def new_item_id():
    sample = int(random.expovariate(1.0) * (MAX_REPO/5))
    return str(min(sample, MAX_REPO))

def new_event(exporter, user_id, item_id):
    exporter.create_event(
        event="star",
        entity_type="user",
        entity_id=user_id,
        target_entity_type="item",
        target_entity_id=item_id)

if __name__ == '__main__':
    main()
